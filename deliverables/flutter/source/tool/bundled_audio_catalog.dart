import 'dart:io';

import 'package:hometongue_tags/models/conversation_episode.dart';

/// The reviewed text assigned to every bundled curriculum audio asset.
///
/// Keep this table explicit: it is both the input to the reproducible Piper
/// generator and the provenance record for the non-theater lesson assets.
const curriculumAudioLines = <String, String>{
  'assets/audio/vietnamese_greeting_full.mp3': 'Cháu chào bà ạ.',
  'assets/audio/vietnamese_greeting_chau_chao.mp3': 'Cháu chào',
  'assets/audio/vietnamese_greeting_ba_a.mp3': 'bà ạ',
  'assets/audio/vietnamese_greeting_example_ong.mp3': 'Cháu chào ông ạ.',
  'assets/audio/vietnamese_greeting_example_me.mp3': 'Con chào mẹ ạ.',
  'assets/audio/vietnamese_greeting_example_chi.mp3': 'Em chào chị ạ.',
  'assets/audio/vietnamese_homecoming_full.mp3': 'Cháu về rồi ạ.',
  'assets/audio/vietnamese_homecoming_chau_ve.mp3': 'Cháu về',
  'assets/audio/vietnamese_homecoming_roi_a.mp3': 'rồi ạ',
  'assets/audio/vietnamese_homecoming_example_con.mp3': 'Con về rồi ạ.',
  'assets/audio/vietnamese_homecoming_example_me.mp3': 'Mẹ về rồi.',
  'assets/audio/vietnamese_homecoming_example_bo.mp3': 'Bố về rồi.',
  'assets/audio/vietnamese_mealtime_full.mp3': 'Cháu mời bà ăn cơm ạ.',
  'assets/audio/vietnamese_mealtime_chau_moi_ba.mp3': 'Cháu mời bà',
  'assets/audio/vietnamese_mealtime_an_com_a.mp3': 'ăn cơm ạ',
  'assets/audio/vietnamese_mealtime_example_bo_me.mp3':
      'Con mời bố mẹ ăn cơm ạ.',
  'assets/audio/vietnamese_mealtime_example_ong.mp3': 'Cháu mời ông ăn cơm ạ.',
  'assets/audio/vietnamese_mealtime_example_ca_nha.mp3': 'Mời cả nhà ăn cơm ạ.',
  'assets/audio/vietnamese_delicious_full.mp3': 'Ngon quá ạ!',
  'assets/audio/vietnamese_delicious_example_canh.mp3': 'Canh ngon quá ạ!',
  'assets/audio/vietnamese_delicious_example_com.mp3': 'Cơm ngon quá ạ!',
  'assets/audio/vietnamese_delicious_example_rau.mp3': 'Rau ngon quá ạ!',
  'assets/audio/vietnamese_short_demo.mp3': 'Đây là nước mắm.',
  'assets/audio/vietnamese_chunk_day_la.mp3': 'Đây là',
  'assets/audio/vietnamese_chunk_nuoc_mam.mp3': 'nước mắm',
  'assets/audio/vietnamese_example_me.mp3': 'Đây là mẹ.',
  'assets/audio/vietnamese_example_nha.mp3': 'Đây là nhà.',
  'assets/audio/vietnamese_example_com.mp3': 'Đây là cơm.',
};

Map<String, String> bundledAudioLines() {
  final lines = <String, String>{...curriculumAudioLines};
  for (final episode in ConversationEpisodeCatalog.defaults) {
    for (final prompt in episode.prompts) {
      for (final line in [
        prompt.elderLine,
        for (final choice in prompt.choices) choice.line,
        for (final choice in prompt.choices) choice.elderReply,
      ]) {
        final path = line.audioPath;
        if (path == null || !path.startsWith('asset://')) {
          throw StateError('Missing bundled audio for ${line.targetText}');
        }
        final relativePath = path.substring('asset://'.length);
        final previous = lines[relativePath];
        if (previous != null && previous != line.targetText) {
          throw StateError(
            'Audio key collision: "$previous" / "${line.targetText}"',
          );
        }
        lines[relativePath] = line.targetText;
      }
    }
  }
  return lines;
}

void main() {
  final entries = bundledAudioLines().entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in entries) {
    stdout.writeln('${entry.key}\t${entry.value}');
  }
}
