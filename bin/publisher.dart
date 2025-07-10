import 'dart:convert';
import 'package:googleapis/pubsub/v1.dart';
import '../lib/config.dart';

Future<void> main() async {
  print('Starting Publisher...');

  // 環境変数を読み込み
  PubSubConfig.loadEnv();

  // Pub/Sub クライアントを作成
  final pubsub = await PubSubConfig.createPubSubClient();
  final topicPath = PubSubConfig.getTopicPath();

  print('Topic: $topicPath');
  print('Sending messages with OrderedKey...\n');

  for (int i = 1; i <= 15; i++) {
    // 一部のメッセージで同じOrderedKeyを使用
    // 例えば、1-5は同じOrderedKeyを使用し、6-15は異なるOrderedKeyを使用
    final orderingKey = (i <= 5)
        ? 'test-key-1' // 最初の5つのメッセージ
        : 'test-key-2'; // 残りのメッセージは異なるOrderedKeyを使用

    final messageData = {
      'id': i,
      'message': 'Message $i',
      'timestamp': DateTime.now().toIso8601String(),
      'orderingKey': orderingKey,
    };

    final publishRequest = PublishRequest()
      ..messages = [
        PubsubMessage()
          ..data = base64Encode(utf8.encode(jsonEncode(messageData)))
          ..orderingKey = orderingKey
          ..attributes = {
            'messageId': i.toString(),
            'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
          }
      ];

    try {
      final response =
          await pubsub.projects.topics.publish(publishRequest, topicPath);
      print('Published Message $i - MessageId: ${response.messageIds?.first}');

      // 少し間隔を空けて送信
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      print('Error publishing Message $i: $e');
    }
  }

  print('\nAll messages published successfully!');
  print('Now run the subscriber to see the ordering behavior.');
}
