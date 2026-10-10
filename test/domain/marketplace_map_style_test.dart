import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  const style = 'alejandrodiscoveryy/cmuxhqa9v00ez01rwegq7703v';
  test('customer uses custom Mapbox style from Admin instead of dark-v11', () {
    final accepted = MarketplaceMapService.applyPublicVisualCapability({
      'capability': 'map_visual',
      'enabled': true,
      'provider_code': 'mapbox',
      'public_token': 'pk.test',
      'config': {
        'style': 'mapbox://styles/$style',
        'tile_size': 256,
      },
    });
    expect(accepted, isTrue);
    expect(MarketplaceMapService.tileUrlTemplate,
        contains('/styles/v1/$style/tiles/256/{z}/{x}/{y}'));
  });

  test('malformed or nonpublic style is rejected', () {
    expect(marketplaceMapboxStylePath('mapbox/dark-v11'), 'mapbox/dark-v11');
    expect(marketplaceMapboxStylePath('mapbox://styles/owner/style'),
        'owner/style');
    expect(marketplaceMapboxStylePath('https://example.test/style'), isNull);
    expect(marketplaceMapboxStylePath('../../secret'), isNull);
    expect(
        MarketplaceMapService.applyPublicVisualCapability({
          'capability': 'map_visual',
          'enabled': false,
          'provider_code': 'mapbox',
          'public_token': 'pk.test',
        }),
        isFalse);
  });
}