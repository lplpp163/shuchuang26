class EducationOpportunity {
  const EducationOpportunity({
    required this.id,
    required this.title,
    required this.organizer,
    required this.summary,
    required this.officialUrl,
    required this.localStoryIdeaId,
    required this.localActionLabel,
    this.opensOn,
    this.closesOn,
    this.fixedStatus,
    this.scheduleLabel,
  });

  final String id;
  final String title;
  final String organizer;
  final String summary;
  final Uri officialUrl;
  final String localStoryIdeaId;
  final String localActionLabel;
  final DateTime? opensOn;
  final DateTime? closesOn;
  final String? fixedStatus;
  final String? scheduleLabel;

  String statusAt(DateTime now) {
    if (fixedStatus case final status?) return status;
    final localDay = DateTime(now.year, now.month, now.day);
    if (opensOn case final opens? when localDay.isBefore(opens)) {
      return '即將收件';
    }
    if (closesOn case final closes? when localDay.isAfter(closes)) {
      return '已截止';
    }
    return '收件中';
  }
}

class EducationOpportunityCatalog {
  const EducationOpportunityCatalog._();

  static final List<EducationOpportunity> official = List.unmodifiable([
    EducationOpportunity(
      id: 'moe-2026-multilingual-reading',
      title: '115年多語多元文化繪本親子共讀甄選',
      organizer: '教育部國民及學前教育署',
      summary: '幼兒園到國中都可參加；由學校統一報名。先和家人共讀，再把文化感受整理成自己的作品。',
      officialUrl: Uri.parse(
        'https://mkm.k12ea.gov.tw/news/17202605110001',
      ),
      localStoryIdeaId: 'family-sharing',
      localActionLabel: '先做一張親子共讀接力',
      opensOn: DateTime(2026, 9, 21),
      closesOn: DateTime(2026, 10, 23),
      scheduleLabel: '收件 2026-09-21～2026-10-23',
    ),
    EducationOpportunity(
      id: 'moe-new-resident-education-portal',
      title: '新住民子女教育資訊網',
      organizer: '教育部國民及學前教育署',
      summary: '查教材、實體與遠距課程、研習及競賽公告。App 只提供入口，不代替官方報名。',
      officialUrl: Uri.parse('https://mkm.k12ea.gov.tw/'),
      localStoryIdeaId: 'class',
      localActionLabel: '先做一張上課故事接力',
      fixedStatus: '持續更新',
      scheduleLabel: '教材・課程・研習・競賽',
    ),
    EducationOpportunity(
      id: 'moe-2026-storytelling-results',
      title: '全國新住民語文說故事競賽成果',
      organizer: '教育部國民及學前教育署',
      summary: '115年賽事已結束；三類題目可作故事靈感，不顯示成仍可報名。',
      officialUrl: Uri.parse(
        'https://www.moe.gov.tw/News_Content.aspx?n=9E7AC85F1954DDA8&s=9C06AFB083644471&sms=169B8E91BB75571F',
      ),
      localStoryIdeaId: 'family-sharing',
      localActionLabel: '把今天的故事說給家人',
      fixedStatus: '已結束・成果參考',
      scheduleLabel: '2026-05-30 已辦理',
    ),
  ]);

  static const checkedOnLabel = '官方資訊查核日：2026-07-14';
}

class StoryIdea {
  const StoryIdea({
    required this.id,
    required this.title,
    required this.prompt,
    required this.draftSource,
    required this.choices,
  });

  final String id;
  final String title;
  final String prompt;
  final String draftSource;
  final List<StorySeedChoice> choices;
}

class StorySeedChoice {
  const StorySeedChoice({
    required this.id,
    required this.label,
    required this.intentZh,
    required this.draftSource,
  });

  final String id;
  final String label;
  final String intentZh;
  final String draftSource;
}

class StoryIdeaCatalog {
  const StoryIdeaCatalog._();

  static const List<StoryIdea> next = [
    StoryIdea(
      id: 'family-sharing',
      title: '和家人分享',
      prompt: '「我今天最想告訴你……」／「後來呢？你覺得怎麼樣？」',
      draftSource: '孩子想和家人分享今天發生的事，想說「我今天最想告訴你……」',
      choices: [
        StorySeedChoice(
          id: 'important-moment',
          label: '今天最重要的一件事',
          intentZh: '我今天最想告訴你一件事。',
          draftSource: '孩子想和家人分享今天發生的事，想說「我今天最想告訴你一件事」',
        ),
        StorySeedChoice(
          id: 'mixed-feeling',
          label: '有件事讓我有點在意',
          intentZh: '有一件事讓我有點在意。',
          draftSource: '孩子想和家人分享今天的感受，想說「有一件事讓我有點在意」',
        ),
      ],
    ),
    StoryIdea(
      id: 'club',
      title: '社團',
      prompt: '「我可以一起參加嗎？」／「這個規則可以再說一次嗎？」',
      draftSource: '孩子想和家人分享社團發生的事，想說「我今天參加社團……」',
      choices: [
        StorySeedChoice(
          id: 'first-club',
          label: '我今天第一次參加社團',
          intentZh: '我今天第一次參加社團。',
          draftSource: '孩子想和家人分享社團發生的事，想說「我今天第一次參加社團」',
        ),
        StorySeedChoice(
          id: 'club-rule',
          label: '有一個規則我還沒聽懂',
          intentZh: '有一個社團規則我還沒聽懂。',
          draftSource: '孩子想和家人分享社團發生的事，想說「有一個社團規則我還沒聽懂」',
        ),
      ],
    ),
    StoryIdea(
      id: 'lunch',
      title: '午餐',
      prompt: '「今天午餐有……」／「這個味道像我們家的哪道菜？」',
      draftSource: '孩子想和家人分享午餐，想說「今天午餐有……」',
      choices: [
        StorySeedChoice(
          id: 'lunch-favorite',
          label: '今天有一道菜我很喜歡',
          intentZh: '今天午餐有一道菜我很喜歡。',
          draftSource: '孩子想和家人分享午餐，想說「今天午餐有一道菜我很喜歡」',
        ),
        StorySeedChoice(
          id: 'lunch-home',
          label: '這個味道讓我想到家裡',
          intentZh: '這個味道讓我想到我們家的菜。',
          draftSource: '孩子想和家人分享午餐，想說「這個味道讓我想到我們家的菜」',
        ),
      ],
    ),
    StoryIdea(
      id: 'class',
      title: '上課',
      prompt: '「我還沒聽懂，可以再說一次嗎？」／「我想分享一個例子。」',
      draftSource: '孩子想和家人分享上課內容，想說「今天上課我學到……」',
      choices: [
        StorySeedChoice(
          id: 'class-learned',
          label: '今天有一件事我學會了',
          intentZh: '今天上課有一件事我學會了。',
          draftSource: '孩子想和家人分享上課內容，想說「今天上課有一件事我學會了」',
        ),
        StorySeedChoice(
          id: 'class-question',
          label: '有一段我還沒有聽懂',
          intentZh: '今天上課有一段我還沒有聽懂。',
          draftSource: '孩子想和家人分享上課內容，想說「今天上課有一段我還沒有聽懂」',
        ),
      ],
    ),
    StoryIdea(
      id: 'friendship',
      title: '朋友關係',
      prompt: '「要不要一起玩？」／「剛才讓你不舒服，對不起，我們可以重來嗎？」',
      draftSource: '孩子想和家人說朋友的事，想說「我想和朋友……」',
      choices: [
        StorySeedChoice(
          id: 'friend-invite',
          label: '我想邀朋友一起玩',
          intentZh: '我想邀朋友一起玩。',
          draftSource: '孩子想和家人說朋友的事，想說「我想邀朋友一起玩」',
        ),
        StorySeedChoice(
          id: 'friend-repair',
          label: '我想和朋友把事情說開',
          intentZh: '我想和朋友把事情說開，再一起重來。',
          draftSource: '孩子想和家人說朋友的事，想說「我想和朋友把事情說開，再一起重來」',
        ),
      ],
    ),
  ];
}
