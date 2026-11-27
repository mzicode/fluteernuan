import 'package:flutter_test/flutter_test.dart';
import 'package:customer/core/i18n/app_localizations.dart';
import 'package:customer/features/chat/utils/system_message_text.dart';

void main() {
  tearDown(() {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
  });

  test('meeting ended event code is localized for chat previews', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);

    expect(resolveServerPreviewText('meeting_ended'), '会议已经结束');
  });

  test('meeting ended event code keeps English when language is English', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.en);

    expect(resolveServerPreviewText('meeting_ended'), 'Meeting ended');
  });

  test('legacy English meeting ended preview is localized', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);

    const preview = 'voice group meeting ended: host_end';
    expect(resolveServerPreviewText(preview), '会议已经结束');
  });

  test('membership system messages resolve to readable text', () {
    const joined = '{"type":"member_joined","user_name":"张三"}';
    const invited = '陆保国 邀请 张庆生 加入了群组';
    const invitedMany = '张志国 邀请 3 位成员加入了群组';
    const left = '海霞 退出了群组';

    expect(resolveSystemMessageText(joined), '张三进入群组');
    expect(resolveSystemMessageText(invited), '陆保国 邀请 张庆生 加入了群组');
    expect(resolveSystemMessageText(invitedMany), '张志国 邀请 3 位成员加入了群组');
    expect(resolveSystemMessageText(left), '海霞 退出了群组');
  });

  test('wallet and other group system messages resolve to readable text', () {
    const claimed = '{"type":"red_packet_claimed","claimer_name":"张三"}';
    const meeting = '{"type":"meeting_started","host_name":"张三"}';
    const muted = '{"type":"member_muted","user_name":"张三"}';

    expect(resolveSystemMessageText(claimed), '张三 领取了红包');
    expect(resolveSystemMessageText(meeting), '张三发起了视频群会议');
    expect(resolveSystemMessageText(muted), '[系统消息]');
  });

  test('membership events accept backend event and action fields', () {
    const joined = '{"event":"member_entered","nickname":"李四"}';
    const left = '{"action":"user_left","name":"王五"}';

    expect(resolveSystemMessageText(joined), '李四进入群组');
    expect(resolveSystemMessageText(left), '王五退出群组');
  });

  test('plain membership notices stay readable', () {
    const joined = '赵六进入群组';
    const left = '赵六退出群组';

    expect(resolveSystemMessageText(joined), '赵六进入群组');
    expect(resolveSystemMessageText(left), '赵六退出群组');
  });

  test('encoded system payloads resolve without exposing raw json', () {
    const joined = '{"type":"member_joined","user_name":"张三"}';
    const unknown = '{"type":"group_notice","payload":{"foo":1}}';

    expect(resolveSystemMessageText(joined), '张三进入群组');
    expect(resolveSystemMessageText(unknown), '[系统消息]');
  });

  test('claimed red packet notices resolve as system text', () {
    const claimed =
        '{"type":"red_packet_claimed","claimer_name":"张三","red_packet_id":"rp-1"}';
    const accepted =
        '{"type":"transfer_accepted","receiver_name":"李四","receiver_id":"u1","amount":10}';

    expect(resolveSystemMessageText(claimed), '张三 领取了红包');
    expect(resolveSystemMessageText(accepted), '李四 已收款');
  });

  test('member mute and unmute system notices are filtered', () {
    expect(
      isMemberMuteSystemMessage('张三已被暖邻官方客服禁言10分钟'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage('张三 已被 暖邻官方客服 禁言 10分钟'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage('张三 已被 暖邻官方客服 解除禁言'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage('李四已被禁言'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage('李四已解除禁言'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage('{"type":"member_muted","user_name":"张三"}'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage('{"type":"member_unmuted","user_name":"张三"}'),
      isTrue,
    );
    expect(
      isMemberMuteSystemMessage(
        '{"type":"group_notice","text":"王五已被暖邻官方客服禁言1小时"}',
      ),
      isTrue,
    );
    expect(isMemberMuteSystemMessage('张三进入群组'), isFalse);
    expect(
      isMemberMuteSystemMessage('{"type":"red_packet_claimed","claimer_name":"张三"}'),
      isFalse,
    );
  });
}
