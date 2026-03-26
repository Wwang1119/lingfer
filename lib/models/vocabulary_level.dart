enum VocabularyLevel {
  zhongkao('中考词汇', code: 'ZK'),
  gaokao('高考词汇', code: 'GK'),
  cet4('四级考点', code: 'CET4'),
  cet6('六级考点', code: 'CET6'),
  kaoyan('考研英语', code: 'KaoYan'),
  ielts('雅思核心', code: 'IELTS'),
  toefl('托福高频', code: 'TOEFL');

  const VocabularyLevel(this.label, {required this.code});
  final String label;
  final String code;
}
