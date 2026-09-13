import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/theme/app_colors.dart';
import '../services/real_name_service.dart';

class RealNamePage extends ConsumerStatefulWidget {
  final VoidCallback? onApproved;

  const RealNamePage({super.key, this.onApproved});

  @override
  ConsumerState<RealNamePage> createState() => _RealNamePageState();
}

class _RealNamePageState extends ConsumerState<RealNamePage> {
  final _realNameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _uuid = const Uuid();

  bool _loading = true;
  bool _statusLoaded = false;
  bool _submitting = false;
  String _error = '';
  RealNameStatus _status = const RealNameStatus();
  XFile? _frontFile;
  XFile? _backFile;
  Uint8List? _frontBytes;
  Uint8List? _backBytes;
  String? _frontRequestId;
  String? _backRequestId;

  String _text({required String zhCN, String? zhTW, required String en}) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadStatus);
  }

  @override
  void dispose() {
    _realNameController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final response = await ref.read(realNameServiceProvider).getStatus();
    if (!mounted) return;
    final status = response.data;
    setState(() {
      _loading = false;
      if (response.isSuccess && status != null) {
        _status = status;
        _statusLoaded = true;
      } else {
        _statusLoaded = false;
        _error = response.message;
      }
    });
    if (response.isSuccess && status?.isApproved == true) {
      widget.onApproved?.call();
    }
  }

  Future<void> _pickDocument(bool front) async {
    if (_submitting) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(_text(zhCN: '拍照', zhTW: '拍照', en: 'Camera')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                  _text(zhCN: '从相册选择', zhTW: '從相簿選擇', en: 'Photo Library')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 2000,
        maxHeight: 1400,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _error = '';
        if (front) {
          _frontFile = file;
          _frontBytes = bytes;
          _frontRequestId = _uuid.v4();
        } else {
          _backFile = file;
          _backBytes = bytes;
          _backRequestId = _uuid.v4();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _text(
          zhCN: '读取认证图片失败',
          zhTW: '讀取認證圖片失敗',
          en: 'Could not read the verification image'));
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final realName = _realNameController.text.trim();
    final idNumber = _idNumberController.text.trim().toUpperCase();
    if (_frontFile == null || _backFile == null) {
      setState(() => _error = _text(
          zhCN: '请上传两张认证图片',
          zhTW: '請上傳兩張認證圖片',
          en: 'Upload two verification images'));
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _submitting = true;
      _error = '';
    });

    try {
      final uploader = ref.read(uploadServiceProvider);
      final frontUrl = await uploader.uploadImage(
        _frontFile!,
        requestId: _frontRequestId,
      );
      if (frontUrl == null || frontUrl.trim().isEmpty) {
        throw StateError(_text(
            zhCN: '认证图片 1 上传失败',
            zhTW: '認證圖片 1 上傳失敗',
            en: 'Failed to upload verification image 1'));
      }
      final backUrl = await uploader.uploadImage(
        _backFile!,
        requestId: _backRequestId,
      );
      if (backUrl == null || backUrl.trim().isEmpty) {
        throw StateError(_text(
            zhCN: '认证图片 2 上传失败',
            zhTW: '認證圖片 2 上傳失敗',
            en: 'Failed to upload verification image 2'));
      }

      final response = await ref.read(realNameServiceProvider).submit(
            realName: realName,
            idNumber: idNumber,
            idFrontUrl: frontUrl,
            idBackUrl: backUrl,
          );
      if (!mounted) return;
      if (!response.isSuccess) {
        setState(() {
          _submitting = false;
          _error = response.message;
        });
        return;
      }

      ref.invalidate(realNameStatusProvider);
      setState(() {
        _submitting = false;
        _status = const RealNameStatus(status: 'pending', canSubmit: false);
        _statusLoaded = true;
        _frontFile = null;
        _backFile = null;
        _frontBytes = null;
        _backBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            zhCN: '实名认证已提交，请等待审核',
            zhTW: '實名認證已提交，請等待審核',
            en: 'Verification submitted for review',
          )),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is StateError
            ? error.message.toString()
            : _text(
                zhCN: '提交失败，请稍后重试',
                zhTW: '提交失敗，請稍後重試',
                en: 'Submission failed. Please try again.',
              );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        title: Text(
            _text(zhCN: '实名认证', zhTW: '實名認證', en: 'Identity Verification')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_statusLoaded
              ? _buildLoadError()
              : RefreshIndicator(
                  onRefresh: _loadStatus,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _buildStatusHeader(isDark),
                      const SizedBox(height: 16),
                      if (_status.canEdit) _buildForm(isDark),
                      if (!_status.canEdit) _buildStatusDetails(isDark),
                    ],
                  ),
                ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 52, color: AppColors.textTertiaryFor(context)),
            const SizedBox(height: 14),
            Text(
              _error.isEmpty
                  ? _text(
                      zhCN: '实名认证状态加载失败',
                      zhTW: '實名認證狀態載入失敗',
                      en: 'Could not load verification status')
                  : _error,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_text(zhCN: '重新加载', zhTW: '重新載入', en: 'Try Again')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(bool isDark) {
    final approved = _status.isApproved;
    final pending = _status.isPending;
    final rejected = _status.isRejected;
    final icon = approved
        ? Icons.verified_rounded
        : pending
            ? Icons.hourglass_top_rounded
            : rejected
                ? Icons.error_outline_rounded
                : Icons.badge_outlined;
    final title = approved
        ? _text(zhCN: '实名认证已通过', zhTW: '實名認證已通過', en: 'Verification Approved')
        : pending
            ? _text(zhCN: '资料审核中', zhTW: '資料審核中', en: 'Under Review')
            : rejected
                ? _text(
                    zhCN: '认证未通过', zhTW: '認證未通過', en: 'Verification Rejected')
                : _text(
                    zhCN: '完成实名认证', zhTW: '完成實名認證', en: 'Verify Your Identity');
    final subtitle = approved
        ? _text(
            zhCN: '你现在可以使用团队和钱包相关功能',
            zhTW: '你現在可以使用團隊和錢包相關功能',
            en: 'Team and wallet features are now available')
        : pending
            ? _text(
                zhCN: '提交成功，审核结果将在这里更新',
                zhTW: '提交成功，審核結果將在這裡更新',
                en: 'Your result will appear here after review')
            : rejected
                ? (_status.rejectReason.isEmpty
                    ? _text(
                        zhCN: '请修改资料后重新提交',
                        zhTW: '請修改資料後重新提交',
                        en: 'Correct the information and submit again')
                    : _status.rejectReason)
                : _text(
                    zhCN: '请使用本人真实有效的身份信息',
                    zhTW: '請使用本人真實有效的身份資訊',
                    en: 'Use your own valid identity information');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.dark
            ? LinearGradient(colors: [
                AppColors.primaryContainerFor(context),
                const Color(0xFF121820),
              ])
            : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 13,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_text(zhCN: '身份信息', zhTW: '身份資訊', en: 'Identity Details'),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _realNameController,
            enabled: !_submitting,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(50)],
            decoration: InputDecoration(
              labelText: _text(zhCN: '真实姓名', zhTW: '真實姓名', en: 'Legal Name'),
              hintText: _text(
                  zhCN: '请输入本人真实姓名',
                  zhTW: '請輸入本人真實姓名',
                  en: 'Enter your legal name'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _idNumberController,
            enabled: !_submitting,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            decoration: InputDecoration(
              labelText: _text(zhCN: '身份证号', zhTW: '身份證號', en: 'ID Number'),
              hintText: _text(
                  zhCN: '请输入身份证号', zhTW: '請輸入身份證號', en: 'Enter your ID number'),
              prefixIcon: const Icon(Icons.credit_card_outlined),
            ),
          ),
          const SizedBox(height: 22),
          Text(_text(zhCN: '认证图片', zhTW: '認證圖片', en: 'Verification Images'),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _text(
              zhCN: '请上传两张清晰图片，具体内容由后端审核',
              zhTW: '請上傳兩張清晰圖片，具體內容由後端審核',
              en: 'Upload two clear images. The backend will review their content.',
            ),
            style: TextStyle(
                fontSize: 12.5, color: AppColors.textSecondaryFor(context)),
          ),
          const SizedBox(height: 14),
          _DocumentPhotoCard(
            title: _text(
                zhCN: '认证图片 1', zhTW: '認證圖片 1', en: 'Verification Image 1'),
            subtitle: _text(
                zhCN: '上传第一张图片', zhTW: '上傳第一張圖片', en: 'Upload the first image'),
            bytes: _frontBytes,
            enabled: !_submitting,
            onTap: () => _pickDocument(true),
          ),
          const SizedBox(height: 12),
          _DocumentPhotoCard(
            title: _text(
                zhCN: '认证图片 2', zhTW: '認證圖片 2', en: 'Verification Image 2'),
            subtitle: _text(
                zhCN: '上传第二张图片',
                zhTW: '上傳第二張圖片',
                en: 'Upload the second image'),
            bytes: _backBytes,
            enabled: !_submitting,
            onTap: () => _pickDocument(false),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_status.isRejected
                      ? _text(zhCN: '重新提交审核', zhTW: '重新提交審核', en: 'Resubmit')
                      : _text(
                          zhCN: '提交认证',
                          zhTW: '提交認證',
                          en: 'Submit Verification')),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _text(
              zhCN: '身份信息仅用于实名认证审核，请确保由本人操作。',
              zhTW: '身份資訊僅用於實名認證審核，請確保由本人操作。',
              en: 'Identity information is used only for verification review.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5, color: AppColors.textTertiaryFor(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDetails(bool isDark) {
    final idDisplay = _status.maskedIdNumber.isNotEmpty
        ? _status.maskedIdNumber
        : (_status.idNumberLast4.isEmpty
            ? ''
            : '**************${_status.idNumberLast4}');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          if (_status.maskedRealName.isNotEmpty)
            _StatusRow(label: '姓名', value: _status.maskedRealName),
          if (idDisplay.isNotEmpty) _StatusRow(label: '身份证号', value: idDisplay),
          if (_status.submittedAt.isNotEmpty)
            _StatusRow(label: '提交时间', value: _status.submittedAt),
          if (_status.reviewedAt.isNotEmpty)
            _StatusRow(label: '审核时间', value: _status.reviewedAt),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_text(
                  zhCN: '刷新审核状态', zhTW: '重新整理審核狀態', en: 'Refresh Status')),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentPhotoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Uint8List? bytes;
  final bool enabled;
  final VoidCallback onTap;

  const _DocumentPhotoCard({
    required this.title,
    required this.subtitle,
    required this.bytes,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.primaryWithOpacity(context, 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: bytes == null
                ? AppColors.primaryWithOpacity(context, 0.16)
                : AppColors.primaryFor(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 34, color: AppColors.primaryFor(context)),
                  const SizedBox(height: 10),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryFor(context))),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes!, fit: BoxFit.cover),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.68),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('重新选择',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(color: AppColors.textSecondaryFor(context))),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
