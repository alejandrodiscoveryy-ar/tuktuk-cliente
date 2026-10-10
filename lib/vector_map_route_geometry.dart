import 'dart:convert';

import 'package:tuktuk_cliente/main.dart' as customer;

// Convierte los puntos del gateway existente a una linea GeoJSON para Mapbox.
// Se respeta el orden [longitud, latitud] y nunca se inventa una ruta recta.
String pilotRouteGeoJson(List<customer.MarketplaceMapPoint> points) =>
    jsonEncode({
      'type': 'FeatureCollection',
      'features': points.length < 2
          ? <Object>[]
          : <Object>[
              {
                'type': 'Feature',
                'geometry': {
                  'type': 'LineString',
                  'coordinates':
                      points.map((point) => [point.lon, point.lat]).toList(),
                },
                'properties': <String, Object>{},
              },
            ],
    });
