import 'package:go_router/go_router.dart';
import '../views/home_view.dart';
import '../views/sender_view.dart';
import '../views/receiver_view.dart';
import '../views/history_view.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeView(),
    ),
    GoRoute(
      path: '/send',
      builder: (context, state) => const SenderView(),
    ),
    GoRoute(
      path: '/receive',
      builder: (context, state) => const ReceiverView(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryView(),
    ),
  ],
);
