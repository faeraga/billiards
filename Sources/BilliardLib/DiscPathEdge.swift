import Foundation

public class DiscPathEdge<k: Field & Comparable> {
	public var coords: Singularities<Vec2<k>>
	public var orientation: Singularity.Orientation
	public var rotationCounts: Singularities<Int>
	
	let ctx: ApexData<k>
	
	public init(
		context: ApexData<k>,
		coords: Singularities<Vec2<k>>,
		orientation: Singularity.Orientation,
		rotationCounts: Singularities<Int>
	) {
		self.ctx = context
		self.coords = coords
		self.orientation = orientation
		self.rotationCounts = rotationCounts
	}
	
	public convenience init(
		context: ApexData<k>,
		coords: Singularities<Vec2<k>>,
		orientation: Singularity.Orientation = .forward
	) {
		self.init(
			context: context,
			coords: coords,
			orientation: orientation,
			rotationCounts: Singularities(0, 0))
	}
	
	public func fromCoords() -> Vec2<k> {
		return coords[orientation.from]
	}
	
	public func toCoords() -> Vec2<k> {
		return coords[orientation.to]
	}
	
	private func _apexCoordsForSide(
		_ side: Side,
		orientation: Singularity.Orientation
	) -> Vec2<k> {
		if orientation == .backward {
			return _apexCoordsForSide(-side, orientation: .forward)
		}
		let baseCoords = coords[.S0]
		let offset = coords[.S1] - coords[.S0]
		var apexCoeff = ctx.coords
		if side == .right {
			apexCoeff = apexCoeff.complexConjugate()
		}
		return baseCoords + offset.complexMul(apexCoeff)
	}
	
	public func apexCoordsForSide(_ side: Side) -> Vec2<k> {
		return _apexCoordsForSide(side, orientation: orientation)
	}

	public func turnedBy(_ turnDegree: Int) -> DiscPathEdge<k> {
		return self.turnedBy(turnDegree, angleBound: nil)!
	}
	
	// result is guaranteed to be non-nil if angleBound is nil
	public func turnedBy(
		_ turnDegree: Int,
		angleBound: AngleBound?
	) -> DiscPathEdge? {
		let rotation = ctx.rotation[orientation.from]

		guard let rotationCoeff = rotation.pow(turnDegree, angleBound: angleBound)
		else { return nil }
		let initialOffset = coords[orientation.to] - coords[orientation.from]
		let newOffset = initialOffset.complexMul(rotationCoeff)
		let newCoords = coords.withValue(
			coords[orientation.from] + newOffset,
			forSingularity: orientation.to)
		
		let newCount = rotationCounts[orientation.from] + turnDegree
		let newRotationCounts =
			rotationCounts.withValue(newCount, forSingularity: orientation.from)
		
		return DiscPathEdge(
			context: ctx,
			coords: newCoords,
			orientation: orientation,
			rotationCounts: newRotationCounts)
	}
	
	public func reversed() -> DiscPathEdge<k> {
		return DiscPathEdge(
			context: ctx,
			coords: coords,
			orientation: -orientation,
			rotationCounts: rotationCounts)
	}
	
	public func isAngleZero() -> Bool {
		return (rotationCounts[.S0] == 0 && rotationCounts[.S1] == 0)
	}

	// a "real" trajectory should always point between self.coords in the
	// direction self.orientation, traevlling in between the left and right
	// apex boundaries. however we do not require this as long as the trajectory
	// exits the disc with a well-defined turn when restricted to the
	// disc nearest the entering edge (i.e. as long as we can follow it
	// geometrically along the covering slice whose discontinuity is the line
	// exiting the target singularity in the direction from the source one).
	public func nextTurnForTrajectory(_ trajectory: Vec3<k>) -> Int? {
		let center = self.toCoords()
		guard let centerSide = PointSide(center, ofTrajectory: trajectory)
		else { return nil }

		let rotation = ctx.rotation[orientation.to]
		let maxTurnMagnitude = rotation.maxTurnMagnitudeForBound(.pi)
		// The offset of the starting boundary apex from the center of the
		// target disc.
		var vZero: Vec2<k>
	
		// The tightest indices we know for the boundary points on each side
		// of the trajectory; i.e. leftBound is the lowest index that is
		// definitely on the left of the trajectory, rightBound is the
		// highest index that is definitely on the right.
		var leftBound, rightBound: Int
	
		if centerSide == .left {
			// widdershins, a positive turn
			vZero = self.apexCoordsForSide(.right) - center
			leftBound = maxTurnMagnitude
			rightBound = 0
		} else {
			// clockwise, a negative turn
			vZero = self.apexCoordsForSide(.left) - center
			leftBound = 0
			rightBound = -maxTurnMagnitude
		}

		while leftBound - rightBound > 1 {
			// testIndex is guaranteed to be strictly between leftBound and
			// rightBound.
			let testIndex = rightBound + (leftBound - rightBound) / 2
			let point = center + vZero.complexMul(rotation.pow(testIndex))
			guard let side = PointSide(point, ofTrajectory: trajectory)
			else { return nil }
			if side == .left {
				leftBound = testIndex
			} else {
				rightBound = testIndex
			}
		}
		// return the bound with highest absolute value
		if centerSide == .left {
			return leftBound
		}
		return rightBound
	}

	public func stepsForTrajectory(_ t: Vec3<k>) -> StepIterator {
		return StepIterator(firstEdge: self, trajectory: t)
	}

	public class Step {
		public let incomingEdge: DiscPathEdge
		public let outgoingEdge: DiscPathEdge
		public let turnDegree: Int

		init(incomingEdge: DiscPathEdge, outgoingEdge: DiscPathEdge, turnDegree: Int) {
			self.incomingEdge = incomingEdge
			self.outgoingEdge = outgoingEdge
			self.turnDegree = turnDegree
		}
	}

	public class StepIterator: Sequence, IteratorProtocol {
		public typealias Element = Step
		
		private let trajectory: Vec3<k>
		private var currentEdge: DiscPathEdge

		init(firstEdge: DiscPathEdge, trajectory: Vec3<k>) {
			self.trajectory = trajectory
			self.currentEdge = firstEdge
		}

		public func next() -> Step? {
			guard let turnDegree = currentEdge.nextTurnForTrajectory(trajectory)
			else { return nil }
			guard let nextEdge = currentEdge.reversed().turnedBy(turnDegree, angleBound: .pi)
			else {
				print("Error (StepIterator): turnedBy should never fail when the input came from nextTurnForTrajectory")
				return nil
			}
			let step = Step(incomingEdge: currentEdge, outgoingEdge: nextEdge, turnDegree: turnDegree)
			self.currentEdge = nextEdge
			return step
		}
	}
}

func OffsetOfCoords<k: Field>(_ v: Vec2<k>, fromTrajectory t: Vec3<k>) -> k {
	return v.x * t.x + v.y * t.y + t.z
}

public func PointSide<k: Field & Comparable>(_ p: Vec2<k>, ofTrajectory t: Vec3<k>) -> Side? {
	let offset = OffsetOfCoords(p, fromTrajectory: t)
	if offset.isZero() {
		return nil
	}
	if offset > k.zero {
		return .left
	}
	return .right
}