import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometongue_tags/models/conversation_episode.dart';

void main() {
  test('every built-in theater line has an existing bundled audio asset', () {
    final audioByPath = <String, String>{};

    for (final episode in ConversationEpisodeCatalog.defaults) {
      for (final prompt in episode.prompts) {
        for (final line in [
          prompt.elderLine,
          for (final choice in prompt.choices) choice.line,
          for (final choice in prompt.choices) choice.elderReply,
        ]) {
          final path = line.audioPath;
          expect(path, isNotNull, reason: line.targetText);
          expect(path, startsWith('asset://assets/audio/theater_'));
          final assetPath = path!.substring('asset://'.length);
          expect(
            File(assetPath).existsSync(),
            isTrue,
            reason: '${line.targetText} -> $assetPath',
          );
          expect(
            File(assetPath).lengthSync(),
            greaterThan(0),
            reason: '${line.targetText} -> $assetPath is empty',
          );
          final previous = audioByPath[path];
          expect(
            previous == null || previous == line.targetText,
            isTrue,
            reason: 'hash collision: $previous / ${line.targetText}',
          );
          audioByPath[path] = line.targetText;
        }
      }
    }

    expect(audioByPath.length, greaterThan(50));
  });
}
