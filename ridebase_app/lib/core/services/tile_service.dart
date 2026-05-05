import 'package:dio/dio.dart';
import '../config.dart';

/// Service to handle tile server connectivity and health checks.
class TileService {
  static final TileService _instance = TileService._internal();

  factory TileService() {
    return _instance;
  }

  TileService._internal();

  late Dio _dio;
  bool _isHealthy = false;
  String _activeTileSource = RideBaseConfig.tileSourceUrl;

  void initialize() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: RideBaseConfig.tileServerTimeout),
        receiveTimeout: Duration(seconds: RideBaseConfig.tileServerTimeout),
        sendTimeout: Duration(seconds: RideBaseConfig.tileServerTimeout),
      ),
    );
  }

  /// Check if the tile server is healthy by attempting to fetch the style metadata.
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get(
        '${RideBaseConfig.tileServerBase}/catalog',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      _isHealthy = response.statusCode == 200;
      if (_isHealthy) {
        _activeTileSource = RideBaseConfig.tileSourceUrl;
      } else {
        _fallbackToLocal();
      }
      return _isHealthy;
    } catch (e) {
      print('Tile server health check failed: $e');
      _fallbackToLocal();
      return false;
    }
  }

  void _fallbackToLocal() {
    _isHealthy = false;
    _activeTileSource = RideBaseConfig.tileSourceUrlLocal;
    print('Falling back to local tile server: $_activeTileSource');
  }

  bool get isHealthy => _isHealthy;
  String get activeTileSource => _activeTileSource;
}
