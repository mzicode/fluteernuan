#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <cwctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring SanitizeProfileId(const std::wstring& raw) {
  size_t start = 0;
  while (start < raw.size() && iswspace(raw[start])) {
    ++start;
  }
  size_t end = raw.size();
  while (end > start && iswspace(raw[end - 1])) {
    --end;
  }
  if (start == end) {
    return L"default";
  }
  const std::wstring trimmed = raw.substr(start, end - start);
  if (trimmed == L"default") {
    return L"default";
  }

  std::wstring value;
  value.reserve(trimmed.size());
  for (size_t i = 0; i < trimmed.size() && value.size() < 48; ++i) {
    const wchar_t ch = trimmed[i];
    const bool safe = (ch >= L'a' && ch <= L'z') || (ch >= L'A' && ch <= L'Z') ||
                      (ch >= L'0' && ch <= L'9') || ch == L'_' || ch == L'-';
    value.push_back(safe ? ch : L'_');
  }
  if (value.empty() || value == L"default") {
    return L"default";
  }
  return value;
}

std::wstring RequestedProfileId() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return L"default";
  }

  std::wstring requested;
  bool found = false;
  const wchar_t* prefix = L"--profile-id=";
  const size_t prefix_length = wcslen(prefix);
  for (int i = 1; i < argc; ++i) {
    if (wcsncmp(argv[i], prefix, prefix_length) == 0) {
      requested = argv[i] + prefix_length;
      found = true;
      break;
    }
    if (wcscmp(argv[i], L"--profile-id") == 0 && i + 1 < argc) {
      requested = argv[++i];
      found = true;
      break;
    }
  }
  ::LocalFree(argv);
  if (!found) {
    return L"default";
  }
  return SanitizeProfileId(requested);
}

std::wstring NewProfileId() {
  FILETIME file_time;
  ::GetSystemTimeAsFileTime(&file_time);
  ULARGE_INTEGER value;
  value.LowPart = file_time.dwLowDateTime;
  value.HighPart = file_time.dwHighDateTime;
  wchar_t buffer[32];
  swprintf_s(buffer, L"instance_%llx", value.QuadPart);
  return buffer;
}

bool AcquireProfileMutex(const std::wstring& profile, HANDLE* mutex) {
  const std::wstring name = L"Local\\NuanLinIM.profile." + profile;
  *mutex = ::CreateMutexW(nullptr, TRUE, name.c_str());
  if (*mutex == nullptr) {
    return false;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::CloseHandle(*mutex);
    *mutex = nullptr;
    return false;
  }
  return true;
}

void AppendQuotedArgument(std::wstring* command, const wchar_t* argument) {
  *command += L" \"";
  for (const wchar_t* cursor = argument; *cursor != L'\0'; ++cursor) {
    if (*cursor == L'"') {
      *command += L"\\\"";
    } else {
      command->push_back(*cursor);
    }
  }
  *command += L"\"";
}

bool RelaunchWithNewProfile() {
  wchar_t exe_path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }

  const std::wstring profile = NewProfileId();
  std::wstring command = L"\"";
  command += exe_path;
  command += L"\" --profile-id=";
  command += profile;

  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv != nullptr) {
    const wchar_t* prefix = L"--profile-id=";
    const size_t prefix_length = wcslen(prefix);
    for (int i = 1; i < argc; ++i) {
      if (wcsncmp(argv[i], prefix, prefix_length) == 0) {
        continue;
      }
      if (wcscmp(argv[i], L"--profile-id") == 0) {
        if (i + 1 < argc) {
          ++i;
        }
        continue;
      }
      AppendQuotedArgument(&command, argv[i]);
    }
    ::LocalFree(argv);
  }

  std::wstring directory(exe_path, length);
  const auto slash = directory.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    directory.resize(slash);
  }

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  std::vector<wchar_t> command_buffer(command.begin(), command.end());
  command_buffer.push_back(L'\0');
  const BOOL created = ::CreateProcessW(
      exe_path, command_buffer.data(), nullptr, nullptr, FALSE, 0, nullptr,
      directory.empty() ? nullptr : directory.c_str(), &startup, &process);
  if (!created) {
    return false;
  }
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // 同一个 profile 只能有一个进程。默认实例已在运行时，再打开程序就启动一个
  // 新的 profile，避免两个窗口抢同一份聊天数据库。
  HANDLE profile_mutex = nullptr;
  if (!AcquireProfileMutex(RequestedProfileId(), &profile_mutex)) {
    const bool relaunched = RelaunchWithNewProfile();
    ::CoUninitialize();
    return relaunched ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"暖邻", origin, size)) {
    if (profile_mutex != nullptr) {
      ::CloseHandle(profile_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (profile_mutex != nullptr) {
    ::CloseHandle(profile_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
