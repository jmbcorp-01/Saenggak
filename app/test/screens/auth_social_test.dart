import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/cognito_auth.dart';
import 'package:saenggak/api/config.dart';
import 'package:saenggak/screens/auth_screen.dart';

Widget wrap(ApiConfig config, {required List<String> used}) => MaterialApp(
  home: AuthScreen(
    auth: CognitoAuth(
      config,
      redirect: Uri.parse('saenggak://auth'),
      browser: (url, scheme) async {
        used.add(url.queryParameters['identity_provider']!);
        throw Exception('closed');
      },
    ),
    signUp: true,
    onSignedIn: () async {},
  ),
);

void main() {
  testWidgets('shows Apple and Google when they are set up', (tester) async {
    final used = <String>[];
    const config = ApiConfig(
      apiUrl: 'x',
      region: 'us-east-1',
      clientId: 'c',
      authDomain: 'auth.saenggak.app',
      signInWith: ['google', 'apple'],
    );
    await tester.pumpWidget(wrap(config, used: used));
    expect(find.byKey(const Key('sign-in-apple')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-google')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-in-google')));
    await tester.pumpAndSettle();
    expect(used, ['Google']);
    // Closing the window is not an error.
    expect(find.text('로그인을 취소했어요.'), findsNothing);
  });

  testWidgets('shows only email until they are set up', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ApiConfig(apiUrl: 'x', region: 'r', clientId: 'c'),
        used: [],
      ),
    );
    expect(find.byKey(const Key('sign-in-apple')), findsNothing);
    expect(find.byKey(const Key('sign-in-google')), findsNothing);
    expect(find.byKey(const Key('email')), findsOneWidget);
  });
}
