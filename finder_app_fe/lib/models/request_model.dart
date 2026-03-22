class OwnershipRequest {
  final int id;
  final String finder;
  final String owner;
  final String foundItemId;
  final String? lostItemId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String finderId;
  final String ownerId;
  final Map<String, dynamic> foundItemDetails;
  final Map<String, dynamic>? lostItemDetails;

  OwnershipRequest({
    required this.id,
    required this.finder,
    required this.owner,
    required this.foundItemId,
    this.lostItemId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.finderId,
    required this.ownerId,
    required this.foundItemDetails,
    this.lostItemDetails,
  });

  factory OwnershipRequest.fromJson(Map<String, dynamic> json) {
    return OwnershipRequest(
      id: json['id'],
      finder: json['finder'].toString(),
      owner: json['owner'].toString(),
      foundItemId: json['found_item'].toString(),
      lostItemId: json['lost_item']?.toString(),
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      finderId: json['finder_id'],
      ownerId: json['owner_id'],
      foundItemDetails: json['found_item_details'],
      lostItemDetails: json['lost_item_details'],
    );
  }
}
