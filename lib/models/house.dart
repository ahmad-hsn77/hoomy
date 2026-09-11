class House {
  final String id;
  final String name;
  final String address;
  final GeoPoint? location;
  final String createdBy;
  final String? specialNumber;

  const House({
    required this.id,
    required this.name,
    required this.address,
    required this.createdBy,
    this.location,
    this.specialNumber,
  });
}

class GeoPoint {
  final double lat;
  final double lng;

  const GeoPoint(this.lat, this.lng);
}
