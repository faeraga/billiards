import Foundation
import Logging
import Dispatch
#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

import BilliardLib

class Commands {
	let logger: Logger

	init(logger: Logger) {
		self.logger = logger
	}

	func run(_ args: [String]) {
		guard let command = args.first
		else {
			print("Usage: billiards [command]")
			exit(1)
		}
		switch command {
		case "pointset":
			let pointSetCommands = PointSetCommands(logger: logger)
			pointSetCommands.run(Array(args[1...]))
		case "repl":
			let repl = BilliardsRepl()
			repl.run()
		default:
			print("Unrecognized command '\(command)'")
		}
	}
}

class BilliardsRepl {
	public init() {
	}

	public func run() {

	}
}

extension Vec2: LosslessStringConvertible
	where R: LosslessStringConvertible
{
	public init?(_ description: String) {
		let components = description.split(separator: ",")
		if components.count != 2 {
			return nil
		}
		guard let x = R.self(String(components[0]))
		else { return nil }
		guard let y = R.self(String(components[1]))
		else { return nil }
		self.init(x, y)
	}

}

/*func colorForResult(_ result: PathFeasibility.Result) -> CGColor? {
	if result.feasible {
		return CGColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 0.4)
	} else if result.apexFeasible && result.baseFeasible {
		return CGColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 0.4)
	} else if result.apexFeasible {
		return CGColor(red: 0.1, green: 0.7, blue: 0.1, alpha: 0.4)
	} else if result.baseFeasible {
		return CGColor(red: 0.1, green: 0.1, blue: 0.7, alpha: 0.4)
	}
	return nil
}*/

class PointSetCommands {
	let logger: Logger
	let dataManager: DataManager

	public init(logger: Logger) {
		self.logger = logger
		let path = FileManager.default.currentDirectoryPath
		let dataURL = URL(fileURLWithPath: path).appendingPathComponent("data")
		dataManager = try! DataManager(
			rootURL: dataURL,
			logger: logger)
	}

	func cmd_create(_ args: [String]) {
		let params = ScanParams(args)

		guard let name: String = params["name"]
		else {
			fputs("pointset create: expected name\n", stderr)
			return
		}
		guard let count: Int = params["count"]
		else {
			fputs("pointset create: expected count\n", stderr)
			return
		}
		let gridDensity: UInt = params["gridDensity"] ?? 32

		let pointSet = RandomApexesWithGridDensity(
			gridDensity, count: count)
		logger.info("Generated point set with density: 2^\(gridDensity), count: \(count)")
		try! dataManager.savePointSet(pointSet, name: name)
	}

	func cmd_list() {
		let sets = try! dataManager.listPointSets()
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		dateFormatter.locale = .current
		dateFormatter.timeZone = .current
		let sortedNames = sets.keys.sorted(by: { (a: String, b: String) -> Bool in
			return a.lowercased() < b.lowercased()
		})
		for name in sortedNames {
			guard let metadata = sets[name]
			else { continue }
			var line = name
			if let count = metadata.count {
				line += " (\(count))"
			}
			if let created = metadata.created {
				let localized = dateFormatter.string(from: created)
				line += " \(localized)"
			}
			print(line)
		}
	}

	func cmd_print(_ args: [String]) {
		let params = ScanParams(args)

		guard let name: String = params["name"]
		else {
			fputs("pointset print: expected name\n", stderr)
			return
		}
		let pointSet = try! dataManager.loadPointSet(name: name)
		for p in pointSet.elements {
			print("\(p.x),\(p.y)")
		}
	}

	func cmd_cycleFilter(_ args: [String]) {
		/*let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset cycleFilter: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset cycleFilter: expected index\n", stderr)
			return
		}
		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles: [Int: TurnCycle] =
			(try? dataManager.loadPath(["pointset", name, "cycles"])) ?? [:]
		guard let cycle = knownCycles[index]
		else {
			fputs("point \(index) has no known cycle", stderr)
			return
		}

		//SimpleCycleFeasibilityForTurnPath
		for coords in pointSet.elements {

		}*/
	}

	func cmd_info(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset info: expected name\n", stderr)
			return
		}
		let indexParam: Int? = params["index"]

		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles: [Int: TurnCycle] =
			(try? dataManager.loadPath(["pointset", name, "cycles"])) ?? [:]

		if let index = indexParam {
			pointSet.printPointIndex(
				index,
				knownCycles: knownCycles,
				precision: 8)
		} else {
			pointSet.summarize(name: name,
				knownCycles: knownCycles)
		}
	}

	func cmd_copyCycles(
		_ args: [String],
		shouldCancel: (() -> Bool)?
	) {
		let params = ScanParams(args)
		guard let fromName: String = params["from"]
		else {
			fputs("pointset copyCycles: expected from\n", stderr)
			return
		}
		guard let toName: String = params["to"]
		else {
			fputs("pointset copyCycles: expected to\n", stderr)
			return
		}
		let neighborCount: Int = params["neighbors"] ?? 1

		let fromSet = try! dataManager.loadPointSet(name: fromName)
		let toSet = try! dataManager.loadPointSet(name: toName)
		let fromCycles = dataManager.knownCyclesForPointSet(
			name: fromName)
		var toCycles = dataManager.knownCyclesForPointSet(
			name: toName)

		let fromRadii = fromSet.elements.map(biradialFromApex)
		let fromPolar = fromSet.elements.map {
			 polarFromCartesian($0.asDoubleVec()) }
		let toRadii = toSet.elements.map(biradialFromApex)
		let toPolar = toSet.elements.map {
			polarFromCartesian($0.asDoubleVec()) }
		func pDistance(fromIndex: Int, toIndex: Int) -> Double {
			let d0 = toPolar[toIndex][.S0] - fromPolar[fromIndex][.S0]
			let d1 = toPolar[toIndex][.S1] - fromPolar[fromIndex][.S1]
			return d0 * d0 + d1 * d1
		}
		func rDistance(fromIndex: Int, toIndex: Int) -> Double {
			let rFrom = fromRadii[fromIndex]
			let rTo = toRadii[toIndex]
			let dr0 = rTo[.S0].asDouble() - rFrom[.S0].asDouble()
			let dr1 = rTo[.S1].asDouble() - rFrom[.S1].asDouble()
			return dr0 * dr0 + dr1 * dr1
		}

		let copyQueue = DispatchQueue(
			label: "me.faec.billiards.copyQueue",
			attributes: .concurrent)
		let resultsQueue = DispatchQueue(
			label: "me.faec.billiards.resultsQueue")
		let copyGroup = DispatchGroup()

		var foundCount = 0
		var updatedCount = 0
		var unchangedCount = 0
		for targetIndex in toSet.elements.indices {
			let targetApex = toSet.elements[targetIndex]
			if shouldCancel?() == true { break }

			copyGroup.enter()
			copyQueue.async {
				defer { copyGroup.leave() }
				if shouldCancel?() == true { return }
				let ctx = ApexData(apex: targetApex)

				let candidates = Array(fromSet.elements.indices).sorted {
					pDistance(fromIndex: $0, toIndex: targetIndex) <
					pDistance(fromIndex: $1, toIndex: targetIndex)
				}.prefix(neighborCount).compactMap
				{ (index: Int) -> TurnCycle? in
					if let cycle = fromCycles[index] {
						if let knownCycle = toCycles[targetIndex] {
							if knownCycle <= cycle {
								return nil
							}
						}
						return cycle
					}
					return nil
				}.sorted { $0 < $1 }

				var foundCycle: TurnCycle? = nil
				var checked: Set<TurnCycle> = []
				for cycle in candidates {
					if shouldCancel?() == true { return }
					if checked.contains(cycle) { continue }
					checked.insert(cycle)

					let result = SimpleCycleFeasibilityForTurnPath(
						cycle.turnPath(), context: ctx)
					if result?.feasible == true {
						foundCycle = cycle
						break
					}
				}
				resultsQueue.sync(flags: .barrier) {
					var caption: String
					if let newCycle = foundCycle {
						if let oldCycle = toCycles[targetIndex] {
							updatedCount += 1
							caption = Magenta("updated ") +
								"length \(oldCycle.length) -> \(newCycle.length)"
						} else {
							foundCount += 1
							caption = "cycle found"
						}
						toCycles[targetIndex] = newCycle
						toSet.printPointIndex(
							targetIndex,
							knownCycles: toCycles,
							precision: 8,
							caption: caption)
					} else {
						unchangedCount += 1
					}
				}
			}
		}
		copyGroup.wait()
		if foundCount > 0 || updatedCount > 0 {
			print("\(foundCount) found, \(updatedCount) updated, \(unchangedCount) unchanged")
			print("saving...")
			try! dataManager.saveKnownCycles(
				toCycles, pointSetName: toName)
		}
	}

	func cmd_validate(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset validate: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset validate: expected index\n", stderr)
			return
		}

		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)

		if index < 0 || index >= pointSet.elements.count {
			fputs("\(name) has no element at index \(index)", stderr)
			return
		}
		let point = pointSet.elements[index]
		guard let cycle = knownCycles[index]
		else {
			fputs("\(name)[\(index)] has no known cycle", stderr)
			return
		}
		let ctx = ApexData(apex: point)
		let result = SimpleCycleFeasibilityForTurnPath(cycle.turnPath(), context: ctx)
		if result?.feasible == true {
			print("Passed!")
		} else {
			print("Failed!")
		}
	}

	func cmd_search(
		_ args: [String],
		shouldCancel: (() -> Bool)?
	) {
		var searchOptions = TrajectorySearchOptions()

		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset search: expected name\n", stderr)
			return
		}
		if let attemptCount: Int = params["attemptCount"] {
			searchOptions.attemptCount = attemptCount
		}
		if let maxPathLength: Int = params["maxPathLength"] {
			searchOptions.maxPathLength = maxPathLength
		}
		if let stopAfterSuccess: Bool = params["stopAfterSuccess"] {
			searchOptions.stopAfterSuccess = stopAfterSuccess
		}
		if let skipKnownPoints: Bool = params["skipKnownPoints"] {
			searchOptions.skipKnownPoints = skipKnownPoints
		}
		let pointSet = try! dataManager.loadPointSet(name: name)
		var knownCycles = dataManager.knownCyclesForPointSet(name: name)
		
		let searchQueue = DispatchQueue(
			label: "me.faec.billiards.searchQueue",
			attributes: .concurrent)
		let resultsQueue = DispatchQueue(label: "me.faec.billiards.resultsQueue")
		let searchGroup = DispatchGroup()

		var activeSearches: [Int: Bool] = [:]
		var searchResults: [Int: TrajectorySearchResult] = [:]
		var foundCount = 0
		var updatedCount = 0
		for (index, point) in pointSet.elements.enumerated() {
			if shouldCancel?() == true { break }

			searchGroup.enter()
			searchQueue.async {
				defer { searchGroup.leave() }
				var options = searchOptions
				var skip = false

				resultsQueue.sync(flags: .barrier) {
					// starting search
					if let cycle = knownCycles[index] {
						if options.skipKnownPoints {
							skip = true
							return
						}
						options.maxPathLength = min(
							options.maxPathLength, cycle.length - 1)
					}
					if shouldCancel?() != true {
						activeSearches[index] = true
					}
				}
				if skip || shouldCancel?() == true { return }

				let searchResult = TrajectorySearchForApexCoords(
					point, options: options, cancel: shouldCancel)
				resultsQueue.sync(flags: .barrier) {
					// search is finished
					activeSearches.removeValue(forKey: index)
					searchResults[index] = searchResult
					var caption = ""
					if let newCycle = searchResult.shortestCycle {
						if let oldCycle = knownCycles[index] {
							if newCycle < oldCycle {
								knownCycles[index] = newCycle
								caption = Magenta("found smaller cycle ") +
									"[\(oldCycle.length) -> \(newCycle.length)]"
								updatedCount += 1
							} else {
								caption = DarkGray("no change")
							}
						} else {
							knownCycles[index] = newCycle
							caption = "cycle found"
							foundCount += 1
						}
					} else if knownCycles[index] != nil {
						caption = DarkGray("no change")
					} else {
						caption = Red("no cycle found")
					}
					
					// reset the current line
					print(ClearCurrentLine(), terminator: "\r")

					pointSet.printPointIndex(
						index,
						knownCycles: knownCycles,
						precision: 4,
						caption: caption)
					
					let failedCount = searchResults.count -
						(foundCount + updatedCount)
					print("found \(foundCount), updated \(updatedCount),",
						"failed \(failedCount).",
						"still active:",
						Cyan("\(activeSearches.keys.sorted())"),
						"...",
						terminator: "")
					fflush(stdout)
				}
			}
		}
		searchGroup.wait()
		print(ClearCurrentLine(), terminator: "\r")
		let failedCount = searchResults.count -
			(foundCount + updatedCount)
		print("found \(foundCount), updated \(updatedCount),",
			"failed \(failedCount).")
		try! dataManager.saveKnownCycles(
			knownCycles, pointSetName: name)
	}

	func cmd_phaseplot(_ args: [String]) {
		/*let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset phaseplot: expected name\n", stderr)
			return
		}*/
		//guard let 
	}

	func cmd_plotConstraint(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset plotConstraint: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset plotConstraint: expected index\n", stderr)
			return
		}
		//let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)
		guard let cycle = knownCycles[index]
		else {
			fputs("no cycle known for index \(index)\n", stderr)
			return
		}
		guard let constraint: ConstraintSpec = params["constraint"]
		else {
			fputs("pointset plotConstraint: expected constraint\n", stderr)
			return
		}
		let path = FileManager.default.currentDirectoryPath
		let paletteURL = URL(fileURLWithPath: path)
			.appendingPathComponent("media")
			.appendingPathComponent("gradient3.png")
		guard let palette = PaletteFromImageFile(paletteURL)
		else {
			fputs("can't load palette\n", stderr)
			return
		}

		let width = 2000
		let height = 1000
		//let pCenter = Vec2()
		let center = Vec2(0.5, 0.25)
		let scale = 1.0 / 1000.0 //0.00045//1.0 / 2200.0
		let image = ImageData(width: width, height: height)

		func colorForCoords(_ z: Vec2<Double>) -> RGB {
			// angle scaled to +-1
			let angle = atan2(z.y, z.x) / Double.pi
			if angle < 0 {
				let positiveAngle = angle + 1.0
				let paletteIndex = Int(positiveAngle * Double(palette.count))
				let rawColor = palette[paletteIndex]
				return RGB(
					r: rawColor.r / 2.0,
					g: rawColor.g / 2.0,
					b: rawColor.b / 2.0)
			}
			let paletteIndex = Int(angle * Double(palette.count - 1))
			return palette[paletteIndex]
		}

		func offsetForTurnPath(
			_ turnPath: TurnPath,
			constraint: ConstraintSpec,
			apex: Vec2<Double>
		) -> Vec2<Double> {
			let baseAngles = Singularities(
				atan2(apex.y, apex.x) * 2.0,
				atan2(apex.y, 1.0 - apex.x) * 2.0)
			var leftTotal = Vec2(0.0, 0.0)
			var rightTotal = Vec2(0.0, 0.0)

			var curAngle = 0.0
			var curOrientation = turnPath.initialOrientation
			for (index, turn) in turnPath.turns.enumerated() {
				let delta = Vec2(cos(curAngle), sin(curAngle))
				let summand = (curOrientation == .forward)
					? delta
					: -delta
				var side: Side
				if constraint.left.index < constraint.right.index {
					if index <= constraint.left.index ||
						index > constraint.right.index
					{
						side = .left
					} else {
						side = .right
					}
				} else if index <= constraint.left.index &&
					index > constraint.right.index
				{
					side = .left
				} else {
					side = .right
				}

				switch side {
					case .left: leftTotal = leftTotal + summand
					case .right: rightTotal = rightTotal + summand
				}
				
				curAngle += baseAngles[curOrientation.to] * Double(turn)
				curOrientation = -curOrientation
			}
			return Vec2(
				x: leftTotal.x * rightTotal.x + leftTotal.y * rightTotal.y,
				y: -leftTotal.x * rightTotal.y + leftTotal.y * rightTotal.x)
		}

		let turnPath = cycle.turnPath()
		for py in 0..<height {
			let y = center.y + Double(height/2 - py) * scale
			for px in 0..<width {
				let x = center.x + Double(px - width/2) * scale
				let z = offsetForTurnPath(turnPath, constraint: constraint, apex: Vec2(x, y))
				let color = colorForCoords(z)
				image.setPixel(row: py, column: px, color: color)
			}
		}

		let imageURL = URL(fileURLWithPath: path)
			.appendingPathComponent("constraint-plot.png")
		image.savePngToUrl(imageURL)

		print("pretending to plot constraint: \(constraint)")
		print("from cycle \(cycle)")
	}

	func cmd_plotOffset(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset plotOffset: expected name\n", stderr)
			return
		}
		guard let index: Int = params["index"]
		else {
			fputs("pointset plotOffset: expected index\n", stderr)
			return
		}
		//let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)
		guard let cycle = knownCycles[index]
		else {
			fputs("no cycle known for index \(index)\n", stderr)
			return
		}
		let path = FileManager.default.currentDirectoryPath
		let paletteURL = URL(fileURLWithPath: path)
			.appendingPathComponent("media")
			.appendingPathComponent("gradient3.png")
		guard let palette = PaletteFromImageFile(paletteURL)
		else {
			fputs("can't load palette\n", stderr)
			return
		}

		let width = 2000
		let height = 1000
		//let pCenter = Vec2()
		let center = Vec2(0.5, 0.25)
		let scale = 1.0 / 1000.0 //0.00045//1.0 / 2200.0
		let image = ImageData(width: width, height: height)

		/*func colorForCoords(_ z: Vec2<Double>) -> RGB {
			// angle scaled to +-1
			var angle = atan2(-z.x, z.y) / Double.pi//atan2(z.y, z.x) / Double.pi
			if angle < 0 {
				let positiveAngle = angle + 1.0
				let paletteIndex = Int(positiveAngle * Double(palette.count))
				let rawColor = palette[paletteIndex]
				return RGB(
					r: rawColor.r / 2.0,
					g: rawColor.g / 2.0,
					b: rawColor.b / 2.0)
			}
			let paletteIndex = Int(angle * Double(palette.count - 1))
			return palette[paletteIndex]
		}*/
		func colorForCoords(_ z: Vec2<Double>) -> RGB {
			let angle = 0.5 + 0.5 * atan2(-z.x, z.y) / Double.pi//atan2(z.y, z.x) / Double.pi
			let paletteIndex = Int(angle * Double(palette.count - 1))
			return palette[paletteIndex]
		}

		func offsetForTurnPath(
			_ turnPath: TurnPath, withApex apex: Vec2<Double>
		) -> Vec2<Double> {
			let baseAngles = Singularities(
				atan2(apex.y, apex.x) * 2.0,
				atan2(apex.y, 1.0 - apex.x) * 2.0)
			var x = 0.0
			var y = 0.0
			var curAngle = 0.0
			var curOrientation = turnPath.initialOrientation
			for turn in turnPath.turns {
				let dx = cos(curAngle)
				let dy = sin(curAngle)
				switch curOrientation {
					case .forward:
						x += dx
						y += dy
					case .backward:
						x -= dx
						y -= dy
				}

				curAngle += baseAngles[curOrientation.to] * Double(turn)
				curOrientation = -curOrientation
			}
			return Vec2(x, y)
		}

		print("Plotting cycle: \(cycle)")

		let turnPath = cycle.turnPath()
		for py in 0..<height {
			let y = center.y + Double(height/2 - py) * scale
			for px in 0..<width {
				let x = center.x + Double(px - width/2) * scale
				let z = offsetForTurnPath(turnPath, withApex: Vec2(x, y))
				let color = colorForCoords(z)
				image.setPixel(row: py, column: px, color: color)
			}
		}

		let imageURL = URL(fileURLWithPath: path)
			.appendingPathComponent("offset-plot.png")
		image.savePngToUrl(imageURL)
	}

	func cmd_plot(_ args: [String]) {
		/*let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset plot: expected name\n", stderr)
			return
		}
		//let pointSet = try! dataManager.loadPointSet(name: name)

		//let outputURL = URL(fileURLWithPath: "plot.png")
		let width = 2000
		let height = 1000
		let scale = Double(width) * 0.9
		let imageCenter = Vec2(Double(width) / 2, Double(height) / 2)
		let modelCenter = Vec2(0.5, 0.25)
		//let pointRadius = CGFloat(4)

		func toImageCoords(_ v: Vec2<Double>) -> Vec2<Double> {
			return (v - modelCenter) * scale + imageCenter
		}
		*/
		//let filter = PathFilter(path: [-2, 2, 2, -2])
		//let feasibility = PathFeasibility(path: [-2, 2, 2, -2])
		//let path = [-2, 2, 2, -2]
		//let path = [4, -3, -5, 3, -4, -4, 5, 4]
		//let turns = [3, -1, 1, -1, -3, 1, -2, 1, -3, -1, 1, -1, 3, 2]
		//let feasibility = SimpleCycleFeasibility(turns: turns)

		/*ContextRenderToURL(outputURL, width: width, height: height)
		{ (context: CGContext) in
			var i = 0
			for point in pointSet.elements {
				//print("point \(i)")
				i += 1
				let modelCoords = point//point.asDoubleVec()

				let color = CGColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 0.6)
				let imageCoords = toImageCoords(modelCoords.asDoubleVec())
				
				context.beginPath()
				//print("point: \(imageCoords.x), \(imageCoords.y)")
				context.addArc(
					center: CGPoint(x: imageCoords.x, y: imageCoords.y),
					radius: pointRadius,
					startAngle: 0.0,
					endAngle: CGFloat.pi * 2.0,
					clockwise: false
				)
				context.closePath()
				context.setFillColor(color)
				context.drawPath(using: .fill)
			}

			// draw the containing half-circle
			context.beginPath()
			let circleCenter = toImageCoords(Vec2(0.5, 0.0))
			context.addArc(center: CGPoint(x: circleCenter.x, y: circleCenter.y),
				radius: CGFloat(0.5 * scale),
				startAngle: 0.0,
				endAngle: CGFloat.pi,
				clockwise: false
			)
			context.closePath()
			context.setStrokeColor(red: 0.1, green: 0.0, blue: 0.2, alpha: 1.0)
			context.setLineWidth(2.0)
			context.drawPath(using: .stroke)
		}*/
	}

	enum CoordinateSystem: String, LosslessStringConvertible {
		case euclidean
		case polar

		public init?(_ str: String) {
			self.init(rawValue: str)
		}

		public var description: String {
			return self.rawValue
		}
	}


	func cmd_probe(_ args: [String]) {
		let params = ScanParams(args)
		guard let name: String = params["name"]
		else {
			fputs("pointset probe: expected name\n", stderr)
			return
		}
		guard let targetCoords: Vec2<Double> = params["coords"]
		else {
			fputs("pointset probe: expected coords\n", stderr)
			return
		}
		let metric: CoordinateSystem =
			params["metric"] ?? .euclidean
		let count: Int = params["count"] ?? 1
		let pointSet = try! dataManager.loadPointSet(name: name)
		let knownCycles = dataManager.knownCyclesForPointSet(name: name)
		let distance: [Double] = pointSet.elements.indices.map { index in
			let point = pointSet.elements[index].asDoubleVec()
			var coords: Vec2<Double>
			switch metric {
				case .euclidean:
					coords = point
				case .polar:
					let angle0 = atan2(point.y, point.x)
					let angle1 = atan2(point.y, 1.0 - point.x)
					coords = Vec2(
						Double.pi / (2.0 * angle0),
						Double.pi / (2.0 * angle1)
					)

			}
			let offset = coords - targetCoords
			return sqrt(offset.x * offset.x + offset.y * offset.y)
		}
		let sortedIndices = pointSet.elements.indices.sorted {
			distance[$0] < distance[$1]
		}

		for index in sortedIndices.prefix(count) {
			let distanceStr = String(format: "%.6f", distance[index])
			pointSet.printPointIndex(index,
				knownCycles: knownCycles,
				precision: 6,
				caption: "(distance \(distanceStr))")
		}
	}

	func cmd_delete(_ args: [String]) {
		guard let name = args.first
		else {
			print("pointset delete: expected point set name")
			exit(1)
		}
		do {
			try dataManager.deletePath(["pointset", name])
			logger.info("Deleted point set '\(name)'")
		} catch {
			logger.error("Couldn't delete point set '\(name)': \(error)")
		}
	}

	func run(_ args: [String]) {
		guard let command = args.first
		else {
			fputs("pointset: expected command", stderr)
			exit(1)
		}
		signal(SIGINT, SIG_IGN)
		let signalQueue = DispatchQueue(label: "me.faec.billiards.signalQueue")
		var sigintCount = 0
		//sigintSrc.suspend()
		let sigintSrc = DispatchSource.makeSignalSource(
			signal: SIGINT,
			queue: signalQueue)
		sigintSrc.setEventHandler {
			print(White("Shutting down..."))
			sigintCount += 1
			if sigintCount > 1 {
				exit(0)
			}
		}
		sigintSrc.resume()
		func shouldCancel() -> Bool {
			return sigintCount > 0
		}

		switch command {
		case "copyCycles":
			cmd_copyCycles(Array(args[1...]),
				shouldCancel: shouldCancel)
		case "create":
			cmd_create(Array(args[1...]))
		case "cycleFilter":
			cmd_cycleFilter(Array(args[1...]))
		case "delete":
			cmd_delete(Array(args[1...]))
		case "info":
			cmd_info(Array(args[1...]))
		case "list":
			cmd_list()
		case "plot":
			cmd_plot(Array(args[1...]))
		case "plotOffset":
			cmd_plotOffset(Array(args[1...]))
		case "plotConstraint":
			cmd_plotConstraint(Array(args[1...]))
		case "print":
			cmd_print(Array(args[1...]))
		case "probe":
			cmd_probe(Array(args[1...]))
		case "search":
			cmd_search(Array(args[1...]),
				shouldCancel: shouldCancel)
		case "validate":
			cmd_validate(Array(args[1...]))
		default:
			print("Unrecognized command '\(command)'")
		}
	}
}



class CycleStats {
	let cycle: TurnCycle
	var pointCount = 0
	init(_ cycle: TurnCycle) {
		self.cycle = cycle
	}
}

struct AggregateStats {
	var totalLength: Int = 0
	var totalWeight: Int = 0
	var totalSegments: Int = 0

	var maxLength: Int = 0
	var maxWeight: Int = 0
	var maxSegments: Int = 0
}

extension Vec2 where R: Numeric {
	func asBiphase() -> Singularities<Double> {
		let xApprox = x.asDouble()
		let yApprox = y.asDouble()
		return Singularities(
			s0: Double.pi / (2.0 * atan2(yApprox, xApprox)),
			s1: Double.pi / (2.0 * atan2(yApprox, 1.0 - xApprox)))
	}
}

func polarFromCartesian(_ coords: Vec2<Double>) -> Singularities<Double> {
	return Singularities(
		Double.pi / (2.0 * atan2(coords.y, coords.x)),
		Double.pi / (2.0 * atan2(coords.y, 1.0 - coords.x)))
}

func biradialFromApex<k: Field>(_ coords: Vec2<k>) -> Singularities<k> {
	return Singularities(coords.x / coords.y, (k.one - coords.x) / coords.y)
}

/*func cartesianFromPolar(_ coords: Vec2<Double>) -> Vec2<Double> {
}*/

struct ConstraintSpec: LosslessStringConvertible {
	let left: Boundary
	let right: Boundary

	enum BoundaryType: String {
		case base
		case apex
	}
	struct Boundary: LosslessStringConvertible {
		let index: Int
		let type: BoundaryType
		init?(_ str: String) {
			let entries = str.split(separator: ",")
			if entries.count != 2 {
				return nil
			}
			guard let index = Int(entries[0])
			else { return nil }
			guard let type = BoundaryType(
				rawValue: String(entries[1]))
			else { return nil }
			self.index = index
			self.type = type
		}

		public var description: String {
			return "\(index),\(type)"
		}
	}

	public init?(_ str: String) {
		let boundaries = str.split(separator: "-")
		if boundaries.count != 2 {
			return nil
		}
		guard let left = Boundary(String(boundaries[0]))
		else { return nil }
		guard let right = Boundary(String(boundaries[1]))
		else { return nil }
		self.left = left
		self.right = right
	}

	public var description: String {
		return "\(left)-\(right)"
	}

}

extension PointSet {
	func printPointIndex(
		_ index: Int,
		knownCycles: [Int: TurnCycle],
		precision: Int = 6,
		caption: String = ""
	) {
		let point = self.elements[index]
		let radii = biradialFromApex(point)
		let pointApprox = point.asDoubleVec()
		let approxAngles = pointApprox.asBiphase().map {
			String(format: "%.\(precision)f", $0) }
		let coordsStr = String(
			format: "(%.\(precision)f, %.\(precision)f)", pointApprox.x, pointApprox.y)
		print(Cyan("[\(index)]"), caption)
		print(Green("  cartesian coords"), coordsStr)
		print(Green("  biradial coords"))
		print(DarkGray("    S0: \(radii[.S0].asDouble())"))
		print("    S1: \(radii[.S1].asDouble())")
		print(Green("  biphase coords"))
		print(DarkGray("    S0: \(approxAngles[.S0])"))
		print("    S1: \(approxAngles[.S1])")
		if let cycle = knownCycles[index] {
			print(Green("  cycle"), cycle)
		}
	}

	func summarize(name: String, knownCycles: [Int: TurnCycle]) {
		var aggregate = AggregateStats()
		var statsTable: [TurnCycle: CycleStats] = [:]
		for (_, cycle) in knownCycles {
			aggregate.totalLength += cycle.length
			aggregate.maxLength = max(aggregate.maxLength, cycle.length)

			aggregate.totalWeight += cycle.weight
			aggregate.maxWeight = max(aggregate.maxWeight, cycle.weight)

			aggregate.totalSegments += cycle.segments.count
			aggregate.maxSegments = max(aggregate.maxSegments, cycle.segments.count)
			
			var curStats: CycleStats
			if let entry = statsTable[cycle] {
				curStats = entry
			} else {
				curStats = CycleStats(cycle)
				statsTable[cycle] = curStats
			}
			curStats.pointCount += 1
		}
		let averageLength = String(format: "%.2f",
			Double(aggregate.totalLength) / Double(knownCycles.count))
		let averageWeight = String(format: "%.2f",
			Double(aggregate.totalWeight) / Double(knownCycles.count))
		let averageSegments = String(format: "%.2f",
			Double(aggregate.totalSegments) / Double(knownCycles.count))
		print("pointset: \(name)")
		print("  known cycles: \(knownCycles.keys.count) / \(self.elements.count)")
		print("  distinct cycles: \(statsTable.count)")
		print("  length: average \(averageLength), maximum \(aggregate.maxLength)")
		print("  weight: average \(averageWeight), maximum \(aggregate.maxWeight)")
		print("  segments: average \(averageSegments), maximum \(aggregate.maxSegments)")
	}
}
