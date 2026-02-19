import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';

enum LegalType { terms, privacy }

class LegalScreen extends ConsumerWidget {
  final LegalType type;
  const LegalScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final title = type == LegalType.terms ? '이용약관' : '개인정보 처리방침';
    final content = type == LegalType.terms ? _termsContent : _privacyContent;

    return Scaffold(
      backgroundColor: t.bg,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 40),
        children: [
          // Back
          Align(
            alignment: Alignment.centerLeft,
            child: AppIconButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Navigator.of(context).pop(),
              backgroundColor: t.card,
              iconColor: t.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          Text(title,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('시행일: 2025년 2월 10일',
              style: TextStyle(color: t.textTertiary, fontSize: 12)),
          const SizedBox(height: 24),

          ...content.map((section) => _buildSection(t, section)),
        ],
      ),
    );
  }

  Widget _buildSection(TteolgaTheme t, _LegalSection section) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(section.body,
              style: TextStyle(
                  color: t.textSecondary,
                  fontSize: 13,
                  height: 1.7)),
        ],
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String body;
  const _LegalSection(this.title, this.body);
}

const _termsContent = [
  _LegalSection(
    '제1조 (목적)',
    '이 약관은 굿딜(이하 "서비스")이 제공하는 실시간 특가 정보 서비스의 이용과 관련하여 '
        '서비스와 이용자 간의 권리, 의무 및 책임 사항을 규정함을 목적으로 합니다.',
  ),
  _LegalSection(
    '제2조 (서비스의 내용)',
    '서비스는 다음과 같은 기능을 제공합니다.\n\n'
        '1. 네이버 쇼핑 등 오픈마켓의 실시간 특가/핫딜 상품 정보 제공\n'
        '2. 상품 가격 비교 및 할인율 정보 제공\n'
        '3. 인기 검색어 및 트렌드 정보 제공\n'
        '4. 카테고리별 상품 탐색 기능\n'
        '5. 관심 카테고리 기반 알림 서비스',
  ),
  _LegalSection(
    '제3조 (서비스 이용)',
    '1. 서비스는 별도의 회원가입 없이 무료로 이용할 수 있습니다.\n'
        '2. 서비스에서 제공하는 상품 정보는 제휴 쇼핑몰의 데이터를 기반으로 하며, '
        '실시간 가격 변동에 따라 실제 가격과 차이가 발생할 수 있습니다.\n'
        '3. 상품의 구매는 해당 쇼핑몰에서 직접 이루어지며, 서비스는 상품 판매의 당사자가 아닙니다.',
  ),
  _LegalSection(
    '제4조 (면책사항)',
    '1. 서비스는 상품 정보의 정확성을 위해 노력하나, 제휴처의 데이터 변경으로 인한 '
        '오류에 대해 책임을 지지 않습니다.\n'
        '2. 서비스를 통해 연결된 외부 쇼핑몰에서의 구매, 결제, 배송, 환불 등에 대해서는 '
        '해당 쇼핑몰의 약관 및 정책이 적용됩니다.\n'
        '3. 천재지변, 서버 장애 등 불가항력으로 인한 서비스 중단에 대해 책임을 지지 않습니다.',
  ),
  _LegalSection(
    '제5조 (지적재산권)',
    '1. 서비스의 디자인, 로고, 소프트웨어 등에 대한 지적재산권은 서비스에 귀속됩니다.\n'
        '2. 상품 이미지 및 정보에 대한 권리는 해당 쇼핑몰 및 판매자에게 귀속됩니다.',
  ),
  _LegalSection(
    '제6조 (약관의 변경)',
    '1. 서비스는 필요한 경우 약관을 변경할 수 있으며, 변경된 약관은 앱 내 공지를 통해 '
        '효력이 발생합니다.\n'
        '2. 변경된 약관에 동의하지 않을 경우 서비스 이용을 중단할 수 있습니다.',
  ),
];

const _privacyContent = [
  _LegalSection(
    '1. 수집하는 개인정보 항목',
    '굿딜은 회원가입을 요구하지 않으며, 서비스 제공을 위해 최소한의 정보만 처리합니다.\n\n'
        '자동 수집 항목:\n'
        '- 기기 정보 (OS 버전, 기기 모델)\n'
        '- 앱 사용 기록 (조회한 상품, 검색어)\n'
        '- 알림 설정 정보 (관심 카테고리, 알림 수신 여부)\n\n'
        '위 정보는 기기 내에 저장되며, 외부 서버로 전송되지 않습니다.',
  ),
  _LegalSection(
    '2. 개인정보의 수집 및 이용 목적',
    '수집된 정보는 다음의 목적으로 이용됩니다.\n\n'
        '- 맞춤형 특가/핫딜 알림 제공\n'
        '- 최근 본 상품 기록 관리\n'
        '- 서비스 개선 및 오류 분석\n'
        '- 앱 이용 통계 분석 (비식별 정보)',
  ),
  _LegalSection(
    '3. 개인정보의 보유 및 이용 기간',
    '- 앱 내 저장 데이터: 앱 삭제 시 즉시 파기\n'
        '- 알림 설정 정보: 사용자가 초기화하거나 앱 삭제 시 파기\n'
        '- 최근 본 상품 기록: 최대 50건까지 기기 내 보관, 앱 삭제 시 파기',
  ),
  _LegalSection(
    '4. 개인정보의 제3자 제공',
    '굿딜은 이용자의 개인정보를 제3자에게 제공하지 않습니다.\n'
        '다만, 다음의 경우에는 예외로 합니다.\n\n'
        '- 이용자가 사전에 동의한 경우\n'
        '- 법령에 의해 요구되는 경우',
  ),
  _LegalSection(
    '5. 광고 관련 안내',
    '서비스는 Google AdMob을 통한 광고를 포함할 수 있습니다.\n'
        'Google의 광고 개인정보 처리방침은 Google 개인정보 처리방침을 따릅니다.\n'
        '광고 식별자(ADID/IDFA)가 광고 표시를 위해 사용될 수 있으며, '
        '기기 설정에서 광고 추적을 제한할 수 있습니다.',
  ),
  _LegalSection(
    '6. 이용자의 권리',
    '이용자는 다음의 권리를 가집니다.\n\n'
        '- 알림 수신 거부: 설정 > 알림 설정에서 변경 가능\n'
        '- 조회 기록 삭제: 앱 데이터 초기화를 통해 삭제 가능\n'
        '- 광고 추적 제한: 기기 설정에서 변경 가능\n'
        '- 앱 삭제를 통한 모든 데이터 즉시 파기',
  ),
  _LegalSection(
    '7. 개인정보 보호책임자',
    '굿딜 서비스 개인정보 관련 문의는 아래로 연락해 주세요.\n\n'
        '이메일: gooddeal.app@gmail.com',
  ),
  _LegalSection(
    '8. 개인정보 처리방침의 변경',
    '이 개인정보 처리방침은 시행일로부터 적용되며, 변경이 있을 경우 '
        '앱 내 공지를 통해 고지합니다.',
  ),
];
