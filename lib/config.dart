import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:googleapis/pubsub/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

class PubSubConfig {
  static final DotEnv _env = DotEnv();

  static String get projectId =>
      _env['PROJECT_ID'] ?? Platform.environment['PROJECT_ID'] ?? '';
  static String get topicName => _env['TOPIC_NAME'] ?? 'test-ordered-topic';
  static String get subscriptionName =>
      _env['SUBSCRIPTION_NAME'] ?? 'test-ordered-subscription';

  static void loadEnv() {
    try {
      _env.load();
    } catch (e) {
      print('Warning: .env file not found, using environment variables');
    }
  }

  static Future<PubsubApi> createPubSubClient() async {
    try {
      // Application Default Credentials (ADC) を使用
      final client = await clientViaApplicationDefaultCredentials(
        scopes: [PubsubApi.pubsubScope],
      );

      return PubsubApi(client);
    } catch (e) {
      throw Exception('Failed to create Pub/Sub client. '
          'Please run "gcloud auth application-default login" first. '
          'Error: $e');
    }
  }

  static String getTopicPath() {
    return 'projects/$projectId/topics/$topicName';
  }

  static String getSubscriptionPath() {
    return 'projects/$projectId/subscriptions/$subscriptionName';
  }
}
