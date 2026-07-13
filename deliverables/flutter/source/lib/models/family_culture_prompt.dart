String familyCulturePromptForEpisode(String episodeId) {
  final id = episodeId.toLowerCase();
  if (id.contains('homecoming')) {
    return '你們家的人回到家時，長輩最常先說哪一句？';
  }
  if (id.contains('morning')) {
    return '長輩小時候，家裡會用哪一句話叫孩子起床？';
  }
  if (id.contains('mealtime')) {
    return '哪一道菜一端上桌，你就知道「這是我們家」？';
  }
  if (id.contains('garden')) {
    return '長輩小時候種過什麼？那個名字用家裡的話怎麼說？';
  }
  if (id.contains('bedtime')) {
    return '長輩小時候最常聽哪個睡前故事或搖籃曲？';
  }
  return '這個場景在你們家真的發生時，家人最常說哪一句？';
}
