import 'dart:convert';
import 'dart:math';
import 'package:googleapis/pubsub/v1.dart';
import '../lib/config.dart';

Future<void> main() async {
  print('Starting Parallel Subscribers...');

  // 環境変数を読み込み
  PubSubConfig.loadEnv();

  print('Subscription: ${PubSubConfig.getSubscriptionPath()}');
  print('Starting 3 parallel subscribers...\n');

  // 3つの並列Subscriberを起動
  final futures = <Future>[];

  for (int i = 1; i <= 3; i++) {
    futures.add(runSubscriber('Subscriber-$i'));
  }

  // すべてのSubscriberを並列実行
  await Future.wait(futures);
}

Future<void> runSubscriber(String subscriberId) async {
  try {
    // 各SubscriberでPub/Subクライアントを作成
    final pubsub = await PubSubConfig.createPubSubClient();
    final subscriptionPath = PubSubConfig.getSubscriptionPath();

    print('[$subscriberId] Started and ready to pull messages');

    while (true) {
      try {
        // 1つずつメッセージをpull
        final pullRequest = PullRequest()..maxMessages = 1;

        final response = await pubsub.projects.subscriptions
            .pull(pullRequest, subscriptionPath);

        if (response.receivedMessages != null &&
            response.receivedMessages!.isNotEmpty) {
          final receivedMessage = response.receivedMessages!.first;
          final message = receivedMessage.message!;

          // メッセージデータをデコード
          final messageData =
              jsonDecode(utf8.decode(base64Decode(message.data!)));
          final pullTime = DateTime.now();

          // ランダムな処理時間（3-8秒）をシミュレート
          final random = Random();
          final sleepSeconds = 3 + random.nextInt(6); // 3-8秒のランダム

          print(
              '[$subscriberId] Pulled: ${messageData['message']} at ${pullTime.toIso8601String()}');
          print('[$subscriberId] Processing for $sleepSeconds seconds...');

          await Future.delayed(Duration(seconds: sleepSeconds));

          // ACK送信
          final ackRequest = AcknowledgeRequest()
            ..ackIds = [receivedMessage.ackId!];

          await pubsub.projects.subscriptions
              .acknowledge(ackRequest, subscriptionPath);

          final ackTime = DateTime.now();
          print(
              '[$subscriberId] ACKed: ${messageData['message']} at ${ackTime.toIso8601String()}');
          print(
              '[$subscriberId] Processing time: ${ackTime.difference(pullTime).inSeconds} seconds\n');
        } else {
          // メッセージがない場合は少し待機
          await Future.delayed(Duration(seconds: 1));
        }
      } catch (e) {
        print('[$subscriberId] Error: $e');
        await Future.delayed(Duration(seconds: 2));
      }
    }
  } catch (e) {
    print('[$subscriberId] Fatal error: $e');
  }
}
