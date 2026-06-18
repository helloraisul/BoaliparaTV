/// Represents a single live TV channel/stream.
class ChannelModel {
  final String id;
  final String name;
  final String logoAsset; // could be asset path or network url
  final String streamUrl;
  final String category;

  const ChannelModel({
    required this.id,
    required this.name,
    required this.logoAsset,
    required this.streamUrl,
    required this.category,
  });
}
