import 'math_3d_object.dart';
import 'math_3d_tool.dart';

/// A point constrained to remain on another scene object.
class PointAttachment {
  final String pointId;
  final String targetId;

  const PointAttachment({required this.pointId, required this.targetId});
}

/// Construction inputs retained so derived geometry can be rebuilt after edits.
class ConstructionDependency {
  final String objectId;
  final ConstructionTool tool;
  final List<Point3D> inputPoints;
  final List<String?> sourcePointIds;
  final Vector3D workingPlaneNormal;
  final int polygonSides;

  ConstructionDependency({
    required this.objectId,
    required this.tool,
    required List<Point3D> inputPoints,
    required List<String?> sourcePointIds,
    required this.workingPlaneNormal,
    required this.polygonSides,
  }) : inputPoints = List.unmodifiable(inputPoints),
       sourcePointIds = List.unmodifiable(sourcePointIds);
}
