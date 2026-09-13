<!-- 个人中心页面 -->
<template>
  <div class="w-full h-full p-0 bg-transparent border-none shadow-none">
    <div class="relative flex-b mt-2.5 max-md:block max-md:mt-1">
      <div class="w-112 mr-5 max-md:w-full max-md:mr-0">
        <div class="art-card-sm relative p-9 pb-6 overflow-hidden text-center">
          <img class="absolute top-0 left-0 w-full h-50 object-cover" src="@imgs/user/bg.webp" />
          <img
            class="relative z-10 w-20 h-20 mt-30 mx-auto object-cover border-2 border-white rounded-full"
            src="@imgs/user/avatar.webp"
          />
          <h2 class="mt-5 text-xl font-normal">{{ userInfo.userName }}</h2>
          <p class="mt-5 text-sm">后台管理中心</p>

          <div class="w-75 mx-auto mt-7.5 text-left">
            <div class="mt-2.5">
              <ArtSvgIcon icon="ri:user-3-line" class="text-g-700" />
              <span class="ml-2 text-sm">系统管理员</span>
            </div>
            <div class="mt-2.5">
              <ArtSvgIcon icon="ri:map-pin-line" class="text-g-700" />
              <span class="ml-2 text-sm">广东省深圳市</span>
            </div>
          </div>
        </div>
      </div>
      <div class="flex-1 overflow-hidden max-md:w-full max-md:mt-3.5">
        <div class="art-card-sm">
          <h1 class="p-4 text-xl font-normal border-b border-g-300">基本设置</h1>

          <ElForm
            :model="form"
            class="box-border p-5 [&>.el-row_.el-form-item]:w-[calc(50%-10px)] [&>.el-row_.el-input]:w-full [&>.el-row_.el-select]:w-full"
            ref="ruleFormRef"
            :rules="rules"
            label-width="86px"
            label-position="top"
          >
            <ElRow>
              <ElFormItem label="姓名" prop="realName">
                <ElInput v-model="form.realName" :disabled="!isEdit" />
              </ElFormItem>
              <ElFormItem label="性别" prop="sex" class="ml-5">
                <ElSelect v-model="form.sex" placeholder="Select" :disabled="!isEdit">
                  <ElOption
                    v-for="item in options"
                    :key="item.value"
                    :label="item.label"
                    :value="item.value"
                  />
                </ElSelect>
              </ElFormItem>
            </ElRow>

            <ElRow>
              <ElFormItem label="昵称" prop="nikeName">
                <ElInput v-model="form.nikeName" :disabled="!isEdit" />
              </ElFormItem>
            </ElRow>

            <ElRow>
              <ElFormItem label="手机" prop="mobile">
                <ElInput v-model="form.mobile" :disabled="!isEdit" />
              </ElFormItem>
              <ElFormItem label="地址" prop="address" class="ml-5">
                <ElInput v-model="form.address" :disabled="!isEdit" />
              </ElFormItem>
            </ElRow>

            <ElFormItem label="个人介绍" prop="des" class="h-32">
              <ElInput type="textarea" :rows="4" v-model="form.des" :disabled="!isEdit" />
            </ElFormItem>

            <div class="flex-c justify-end [&_.el-button]:!w-27.5">
              <ElButton type="primary" class="w-22.5" v-ripple @click="edit">
                {{ isEdit ? '保存' : '编辑' }}
              </ElButton>
            </div>
          </ElForm>
        </div>

        <div class="art-card-sm my-5">
          <h1 class="p-4 text-xl font-normal border-b border-g-300">更改密码</h1>

          <ElForm
            ref="pwdFormRef"
            :model="pwdForm"
            :rules="pwdRules"
            class="box-border p-5"
            label-width="86px"
            label-position="top"
          >
            <ElFormItem label="当前密码" prop="password">
              <ElInput
                v-model="pwdForm.password"
                type="password"
                :disabled="!isEditPwd"
                show-password
                placeholder="请输入当前密码"
              />
            </ElFormItem>

            <ElFormItem label="新密码" prop="newPassword">
              <ElInput
                v-model="pwdForm.newPassword"
                type="password"
                :disabled="!isEditPwd"
                show-password
                placeholder="请输入新密码（至少6位）"
              />
            </ElFormItem>

            <ElFormItem label="确认新密码" prop="confirmPassword">
              <ElInput
                v-model="pwdForm.confirmPassword"
                type="password"
                :disabled="!isEditPwd"
                show-password
                placeholder="请再次输入新密码"
              />
            </ElFormItem>

            <div class="flex-c justify-end gap-3">
              <ElButton v-if="isEditPwd" @click="cancelEditPwd"> 取消 </ElButton>
              <ElButton type="primary" v-ripple @click="editPwd" :loading="pwdLoading">
                {{ isEditPwd ? '保存' : '编辑' }}
              </ElButton>
            </div>
          </ElForm>
        </div>

        <div class="art-card-sm my-5 p-5">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h1 class="text-xl font-normal">Google Authenticator</h1>
              <p class="mt-2 text-sm text-g-500">
                {{
                  totpEnabled
                    ? '已启用，后台登录时需要输入 6 位动态验证码'
                    : '为当前管理员账号绑定 Google Authenticator'
                }}
              </p>
            </div>
            <ElTag :type="totpEnabled ? 'success' : 'info'">
              {{ totpEnabled ? '已启用' : '未启用' }}
            </ElTag>
          </div>

          <div v-if="totpUri" class="mt-5 flex flex-wrap items-start gap-6">
            <QrcodeVue :value="totpUri" :size="180" level="M" />
            <div class="min-w-0 flex-1 text-sm">
              <p>请使用 Google Authenticator 扫描二维码。</p>
              <p class="mt-3 break-all font-mono text-xs text-g-500">密钥：{{ totpSecret }}</p>
              <ElInput
                v-model="totpForm.password"
                class="mt-4"
                type="password"
                show-password
                placeholder="当前管理员密码"
              />
              <ElInput
                v-model="totpForm.code"
                class="mt-3"
                maxlength="6"
                inputmode="numeric"
                placeholder="输入 6 位动态验证码"
              />
              <ElButton class="mt-4" type="primary" :loading="totpLoading" @click="enableTotp"
                >确认启用</ElButton
              >
            </div>
          </div>

          <div v-else class="mt-5 flex flex-wrap items-center gap-3">
            <ElButton
              v-if="!totpEnabled"
              type="primary"
              :loading="totpLoading"
              @click="startTotpSetup"
            >
              绑定 Google Authenticator
            </ElButton>
            <template v-else>
              <ElInput
                v-model="disableTotpForm.password"
                class="max-w-60"
                type="password"
                show-password
                placeholder="当前管理员密码"
              />
              <ElInput
                v-model="disableTotpForm.code"
                class="max-w-52"
                maxlength="6"
                inputmode="numeric"
                placeholder="6 位动态验证码"
              />
              <ElButton type="danger" plain :loading="totpLoading" @click="disableTotp"
                >停用验证</ElButton
              >
            </template>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { useUserStore } from '@/store/modules/user'
  import {
    disableAdminTotp,
    enableAdminTotp,
    getAdminTotpStatus,
    setupAdminTotp,
    updateAdminPassword
  } from '@/api/admin'
  import QrcodeVue from 'qrcode.vue'
  import { ElMessage, type FormInstance, type FormRules } from 'element-plus'

  defineOptions({ name: 'UserCenter' })

  const userStore = useUserStore()
  const userInfo = computed(() => userStore.getUserInfo)

  const isEdit = ref(false)
  const isEditPwd = ref(false)
  const pwdLoading = ref(false)
  const date = ref('')
  const ruleFormRef = ref<FormInstance>()
  const pwdFormRef = ref<FormInstance>()
  const totpEnabled = ref(false)
  const totpUri = ref('')
  const totpSecret = ref('')
  const totpLoading = ref(false)
  const totpForm = reactive({ password: '', code: '' })
  const disableTotpForm = reactive({ password: '', code: '' })

  /**
   * 用户信息表单
   */
  const form = reactive({
    realName: '管理员',
    nikeName: '管理员',
    mobile: '18888888888',
    address: '中国',
    sex: '1',
    des: '后台管理中心'
  })

  /**
   * 密码修改表单
   */
  const pwdForm = reactive({
    password: '',
    newPassword: '',
    confirmPassword: ''
  })

  /**
   * 确认密码验证
   */
  const validateConfirmPassword = (_rule: any, value: string, callback: any) => {
    if (value !== pwdForm.newPassword) {
      callback(new Error('两次输入的密码不一致'))
    } else {
      callback()
    }
  }

  /**
   * 密码表单验证规则
   */
  const pwdRules = reactive<FormRules>({
    password: [{ required: true, message: '请输入当前密码', trigger: 'blur' }],
    newPassword: [
      { required: true, message: '请输入新密码', trigger: 'blur' },
      { min: 6, message: '密码长度至少6位', trigger: 'blur' }
    ],
    confirmPassword: [
      { required: true, message: '请确认新密码', trigger: 'blur' },
      { validator: validateConfirmPassword, trigger: 'blur' }
    ]
  })

  /**
   * 表单验证规则
   */
  const rules = reactive<FormRules>({
    realName: [
      { required: true, message: '请输入姓名', trigger: 'blur' },
      { min: 2, max: 50, message: '长度在 2 到 50 个字符', trigger: 'blur' }
    ],
    nikeName: [
      { required: true, message: '请输入昵称', trigger: 'blur' },
      { min: 2, max: 50, message: '长度在 2 到 50 个字符', trigger: 'blur' }
    ],
    mobile: [{ required: true, message: '请输入手机号码', trigger: 'blur' }],
    address: [{ required: true, message: '请输入地址', trigger: 'blur' }],
    sex: [{ required: true, message: '请选择性别', trigger: 'blur' }]
  })

  /**
   * 性别选项
   */
  const options = [
    { value: '1', label: '男' },
    { value: '2', label: '女' }
  ]

  const loadTotpStatus = async () => {
    try {
      const result = await getAdminTotpStatus()
      totpEnabled.value = Boolean(result.totp_enabled)
    } catch {
      totpEnabled.value = false
    }
  }

  const startTotpSetup = async () => {
    totpLoading.value = true
    try {
      const result = await setupAdminTotp()
      totpUri.value = result.otpauth_uri
      totpSecret.value = result.secret
      ElMessage.success('绑定密钥已生成，请使用 Google Authenticator 扫码')
    } catch (error: any) {
      ElMessage.error(error?.message || '生成绑定密钥失败')
    } finally {
      totpLoading.value = false
    }
  }

  const enableTotp = async () => {
    if (!totpForm.password || !/^\d{6}$/.test(totpForm.code)) {
      ElMessage.warning('请输入当前密码和 6 位动态验证码')
      return
    }
    totpLoading.value = true
    try {
      await enableAdminTotp(totpForm)
      totpEnabled.value = true
      totpUri.value = ''
      totpSecret.value = ''
      totpForm.password = ''
      totpForm.code = ''
      ElMessage.success('Google Authenticator 已启用')
    } catch (error: any) {
      ElMessage.error(error?.message || '启用 Google Authenticator 失败')
    } finally {
      totpLoading.value = false
    }
  }

  const disableTotp = async () => {
    if (!disableTotpForm.password || !/^\d{6}$/.test(disableTotpForm.code)) {
      ElMessage.warning('请输入当前密码和 6 位动态验证码')
      return
    }
    totpLoading.value = true
    try {
      await disableAdminTotp(disableTotpForm)
      totpEnabled.value = false
      disableTotpForm.password = ''
      disableTotpForm.code = ''
      ElMessage.success('Google Authenticator 已停用')
    } catch (error: any) {
      ElMessage.error(error?.message || '停用 Google Authenticator 失败')
    } finally {
      totpLoading.value = false
    }
  }

  onMounted(() => {
    getDate()
    loadTotpStatus()
  })

  /**
   * 根据当前时间获取问候语
   */
  const getDate = () => {
    const h = new Date().getHours()

    if (h >= 6 && h < 9) date.value = '早上好'
    else if (h >= 9 && h < 11) date.value = '上午好'
    else if (h >= 11 && h < 13) date.value = '中午好'
    else if (h >= 13 && h < 18) date.value = '下午好'
    else if (h >= 18 && h < 24) date.value = '晚上好'
    else date.value = '很晚了，早点睡'
  }

  /**
   * 切换用户信息编辑状态
   */
  const edit = () => {
    isEdit.value = !isEdit.value
  }

  /**
   * 切换密码编辑状态或保存密码
   */
  const editPwd = async () => {
    if (!isEditPwd.value) {
      // 进入编辑模式
      isEditPwd.value = true
      return
    }

    // 保存密码
    if (!pwdFormRef.value) return

    try {
      const valid = await pwdFormRef.value.validate()
      if (!valid) return

      pwdLoading.value = true
      // 密码字段只在校验通过并确认保存时发送，不进入普通用户资料表单。
      await updateAdminPassword({
        old_password: pwdForm.password,
        new_password: pwdForm.newPassword
      })

      ElMessage.success('密码修改成功')
      isEditPwd.value = false
      // 清空表单
      pwdForm.password = ''
      pwdForm.newPassword = ''
      pwdForm.confirmPassword = ''
    } catch (error: any) {
      ElMessage.error(error?.message || '密码修改失败')
    } finally {
      pwdLoading.value = false
    }
  }

  /**
   * 取消编辑密码
   */
  const cancelEditPwd = () => {
    isEditPwd.value = false
    // 离开编辑态时同时清空敏感值和历史校验结果，避免下次打开时残留。
    pwdForm.password = ''
    pwdForm.newPassword = ''
    pwdForm.confirmPassword = ''
    pwdFormRef.value?.clearValidate()
  }
</script>
