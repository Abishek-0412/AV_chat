import 'package:av_protocol/av_protocol.dart';
import 'package:test/test.dart';

void main() {
  final key = List<int>.generate(32, (i) => i);

  test('fromPublicKey is stable and well formed', () {
    final id = AvId.fromPublicKey(key);
    expect(id, AvId.fromPublicKey(key));
    expect(
      id.value,
      matches(RegExp(r'^AV-[A-Z2-7]{4}-[A-Z2-7]{4}-[A-Z2-7]{4}$')),
    );
  });

  test('different keys give different ids', () {
    final other = List<int>.generate(32, (i) => i + 1);
    expect(AvId.fromPublicKey(key), isNot(AvId.fromPublicKey(other)));
  });

  test('tryParse accepts sloppy user input', () {
    final id = AvId.fromPublicKey(key);
    final sloppy = id.value.toLowerCase().replaceAll('-', ' ');
    expect(AvId.tryParse(sloppy), id);
    expect(AvId.tryParse(id.value.substring(3)), id);
  });

  test('tryParse rejects bad input', () {
    expect(AvId.tryParse(''), isNull);
    expect(AvId.tryParse('AV-AAAA-AAAA'), isNull);
    expect(AvId.tryParse('AV-AAAA-AAAA-AAA1'), isNull);
    expect(() => AvId.parse('nope'), throwsFormatException);
  });
}
