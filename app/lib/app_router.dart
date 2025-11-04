import 'package:flutter/material.dart';
import 'features/venues/screens/map_screen.dart';

class _Delegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: const [
        MaterialPage(child: MapScreen()),
      ],
      onPopPage: (route, result) => route.didPop(result),
    );
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

final _delegate = _Delegate();
RouterConfig<Object> buildRouter() => RouterConfig(
  routerDelegate: _delegate,
  routeInformationParser: const _Parser(),
);

class _Parser extends RouteInformationParser<Object> {
  const _Parser();
  @override
  Future<Object> parseRouteInformation(RouteInformation routeInformation) async => Object();
}
