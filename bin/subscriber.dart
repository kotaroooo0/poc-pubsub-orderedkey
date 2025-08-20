import 'dart:convert';
import 'dart:math';
import 'package:googleapis/pubsub/v1.dart';
import 'package:args/args.dart';
import '../lib/config.dart';

Future<void> main(List<String> arguments) async {
  // コマンドライン引数の設定
  final parser = ArgParser()
    ..addOption('subscribers',
        abbr: 's', defaultsTo: '3', help: 'Number of parallel subscribers')
    ..addOption('max-messages',
        abbr: 'm',
        defaultsTo: '3',
        help: 'Maximum messages to pull per request')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show this help message');

  try {
    final results = parser.parse(arguments);

    // ヘルプ表示
    if (results['help']) {
      print('Google Cloud Pub/Sub OrderedKey Subscriber');
      print('');
      print('Usage: dart run bin/subscriber.dart [options]');
      print('');
      print('Options:');
      print(parser.usage);
      print('');
      print('Examples:');
      print('  dart run bin/subscriber.dart --subscribers=5 --max-messages=10');
      print('  dart run bin/subscriber.dart -s 2 -m 1 -t 5');
      return;
    }

    // 引数の解析とバリデーション
    final subscriberCount = int.tryParse(results['subscribers']) ?? 3;
    final maxMessages = int.tryParse(results['max-messages']) ?? 3;

    if (subscriberCount < 1 || subscriberCount > 20) {
      print('Error: Subscriber count must be between 1 and 20');
      return;
    }

    if (maxMessages < 1 || maxMessages > 100) {
      print('Error: Max messages must be between 1 and 100');
      return;
    }

    print('Starting Parallel Subscribers...');
    print('Configuration:');
    print('  - Subscribers: $subscriberCount');
    print('  - Max Messages: $maxMessages');

    // 環境変数を読み込み
    PubSubConfig.loadEnv();

    print('Subscription: ${PubSubConfig.getSubscriptionPath()}');
    print('Starting $subscriberCount parallel subscribers...\n');

    final rand = Random();
    // 指定された数の並列Subscriberを起動
    final futures = <Future>[];
    for (int i = 1; i <= subscriberCount; i++) {
      futures.add(
          runSubscriber('Subscriber-$i', maxMessages, rand.nextInt(3) + 1));
    }

    // すべてのSubscriberを並列実行
    await Future.wait(futures);
  } catch (e) {
    print('Error parsing arguments: $e');
    print('Use --help for usage information');
  }
}

Future<void> runSubscriber(
    String subscriberId, int maxMessages, int sleepTime) async {
  try {
    // 各SubscriberでPub/Subクライアントを作成
    final pubsub = await PubSubConfig.createPubSubClient();
    final subscriptionPath = PubSubConfig.getSubscriptionPath();

    print(
        '[$subscriberId] Started and ready to pull messages (maxMessages: $maxMessages, sleepTime: ${sleepTime}s)');

    while (true) {
      try {
        // 指定された数のメッセージをpull
        final pullRequest = PullRequest()..maxMessages = maxMessages;

        final response = await pubsub.projects.subscriptions
            .pull(pullRequest, subscriptionPath);

        if (response.receivedMessages != null &&
            response.receivedMessages!.isNotEmpty) {
          final batchStartTime = DateTime.now();
          final messageCount = response.receivedMessages!.length;

          print(
              '📦 [$subscriberId] BATCH PULLED: $messageCount messages at ${batchStartTime.toIso8601String()}');

          // 全ての受信メッセージを処理
          final ackIds = <String>[];

          for (int i = 0; i < response.receivedMessages!.length; i++) {
            final receivedMessage = response.receivedMessages![i];
            final message = receivedMessage.message!;

            // メッセージデータをデコード
            final messageData =
                jsonDecode(utf8.decode(base64Decode(message.data!)));
            final pullTime = DateTime.now();

            print(
                '🔄 [$subscriberId] Processing Message ${i + 1}/$messageCount: ${messageData['message']} (ID: ${messageData['id']}, OrderedKey: ${messageData['orderingKey']})');

            // ACK用のIDを収集
            ackIds.add(receivedMessage.ackId!);

            final processTime = DateTime.now();
            print(
                '✅ [$subscriberId] Processed: ${messageData['message']} (ID: ${messageData['id']}) - ${processTime.difference(pullTime).inSeconds}s');
          }

          // 指定された処理時間をシミュレート
          print('⏳ [$subscriberId] Processing for $sleepTime seconds...');
          await Future.delayed(Duration(seconds: sleepTime));

          // 全メッセージをまとめてACK
          final ackRequest = AcknowledgeRequest()..ackIds = ackIds;
          await pubsub.projects.subscriptions
              .acknowledge(ackRequest, subscriptionPath);

          final batchEndTime = DateTime.now();
          print(
              '🎯 [$subscriberId] BATCH ACKED: $messageCount messages at ${batchEndTime.toIso8601String()}');
          print(
              '⏱️  [$subscriberId] Total Batch Time: ${batchEndTime.difference(batchStartTime).inSeconds} seconds');
          print(
              '═══════════════════════════════════════════════════════════════\n');
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
