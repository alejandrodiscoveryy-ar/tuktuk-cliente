import 'package:flutter_test/flutter_test.dart';
import 'package:tuktuk_cliente/main.dart';

void main() {
  test('vector map keeps the complete custom style from Admin', () {
    const style = 'alejandrodiscoveryy/cmuxhqa9v00ez01rwegq7703v';
    expect(MarketplaceMapService.applyPublicVisualCapability({
      'capability': 'map_visual',
      'enabled': true,
      'provider_code': 'mapbox',
      'public_token': 'pk.test',
      'config': {'style': 'mapbox://styles/$style', 'tile_size': 256}
    }), isTrue);
    expect(MarketplaceMapService.vectorStyleUri,
        'mapbox://styles/$style');
  });
}
