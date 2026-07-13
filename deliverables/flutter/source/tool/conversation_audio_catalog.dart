import 'dart:io';

import 'package:hometongue_tags/models/conversation_episode.dart';

/// Prints the deterministic asset path and reviewed text for every unique
/// bundled theater line. This is intentionally generator-agnostic: a maintainer
/// can replace any MP3 with a family or native-speaker recording without
/// changing application code.
void main() {
  final lines = <String, String>{};
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
        final previous = lines[path];
        if (previous != null && previous != line.targetText) {
          throw StateError(
              'Audio key collision: "$previous" / "${line.targetText}"');
        }
        lines[path] = line.targetText;
      }
    }
  }

  final entries = lines.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in entries) {
    stdout.writeln(
      '${entry.key.substring('asset://'.length)}\t${entry.value}',
    );
  }
}
