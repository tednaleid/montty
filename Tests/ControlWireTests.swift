import Foundation
import Testing

@Suite struct ControlWireTests {
    @Test func decodesASetColorRequest() throws {
        let json = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"surface",
         "prop":"color","value":["neutralBright","#1a7f37"]}
        """.utf8)
        let request = try ControlRequest.decode(json)
        #expect(request.surface == "M1")
        #expect(request.command == .setColor(
            scope: .surface,
            tint: PaneTint(stops: [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        ))
    }

    @Test func aNullValueIsTheClearForm() throws {
        let json = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"tab","prop":"color","value":null}
        """.utf8)
        #expect(try ControlRequest.decode(json).command == .clearColor(scope: .tab))
    }

    @Test func decodesNameAndStatus() throws {
        let name = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"name","value":"MR !123"}
        """.utf8)
        #expect(try ControlRequest.decode(name).command == .setName("MR !123"))

        let clear = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"name","value":null}
        """.utf8)
        #expect(try ControlRequest.decode(clear).command == .clearName)

        let status = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"status","value":"waiting"}
        """.utf8)
        #expect(try ControlRequest.decode(status).command == .setStatus(.waiting))

        let cleared = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"status","value":null}
        """.utf8)
        #expect(try ControlRequest.decode(cleared).command == .setStatus(nil))
    }

    @Test func decodesInfo() throws {
        let json = Data("{\"v\":1,\"cmd\":\"info\",\"surface\":\"M1\"}".utf8)
        #expect(try ControlRequest.decode(json).command == .info)
    }

    @Test func rejectsANewerProtocolVersion() {
        let json = Data("{\"v\":2,\"cmd\":\"info\",\"surface\":\"M1\"}".utf8)
        #expect(throws: ControlRequest.DecodeFailure.unsupportedVersion) {
            try ControlRequest.decode(json)
        }
    }

    @Test func aMessageWithNoCmdIsALegacyHook() {
        let json = Data("{\"event\":\"stop\",\"surface\":\"M1\",\"cwd\":\"/tmp\"}".utf8)
        #expect(throws: ControlRequest.DecodeFailure.legacyHook) {
            try ControlRequest.decode(json)
        }
    }

    @Test func rejectsGarbage() {
        #expect(throws: ControlRequest.DecodeFailure.malformed) {
            try ControlRequest.decode(Data("{ not json".utf8))
        }
    }

    @Test func aMissingValueKeyIsMalformed() {
        let color = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"tab","prop":"color"}
        """.utf8)
        #expect(throws: ControlRequest.DecodeFailure.malformed) {
            try ControlRequest.decode(color)
        }

        let name = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"name"}
        """.utf8)
        #expect(throws: ControlRequest.DecodeFailure.malformed) {
            try ControlRequest.decode(name)
        }
    }

    @Test func rejectsMoreThanMaxStops() {
        let json = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"tab","prop":"color",
         "value":["red","green","blue","cyan"]}
        """.utf8)
        #expect(throws: ControlRequest.DecodeFailure.malformed) {
            try ControlRequest.decode(json)
        }
    }

    @Test func rejectsAnUnparseableStop() {
        let json = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"tab","prop":"color",
         "value":["green","chartreuse"]}
        """.utf8)
        #expect(throws: ControlRequest.DecodeFailure.malformed) {
            try ControlRequest.decode(json)
        }
    }

    @Test func requestRoundTripsThroughEncoding() throws {
        let request = ControlRequest(
            surface: "M1",
            command: .setColor(scope: .repo, tint: PaneTint(stops: [.named(.cyan)]))
        )
        let decoded = try ControlRequest.decode(try request.encoded())
        #expect(decoded.command == request.command)
        #expect(decoded.surface == "M1")
    }

    @Test func otherCommandShapesRoundTripThroughEncoding() throws {
        let commands: [ControlCommand] = [
            .setName("MR !123"),
            .clearName,
            .setStatus(.waiting),
            .clearColor(scope: .surface)
        ]
        for command in commands {
            let request = ControlRequest(surface: "M1", command: command)
            let decoded = try ControlRequest.decode(try request.encoded())
            #expect(decoded.command == command)
            #expect(decoded.surface == "M1")
        }
    }

    @Test func encodesResponses() throws {
        let okBody = String(data: try ControlResponse.ok.encoded(), encoding: .utf8)
        #expect(okBody == "{\"ok\":true}")

        let failure = try ControlResponse.failure("unknown surface").encoded()
        let parsed = try JSONSerialization.jsonObject(with: failure) as? [String: Any]
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "unknown surface")
    }

    @Test func infoResponseCarriesOkAlongsideSnakeCasedFields() throws {
        let info = ControlInfo(
            surfaceID: "M1", leafID: "L1", tabID: "T1",
            tabName: "montty/", tabNameIsOverride: false,
            scopes: ControlInfo.Scopes(surface: nil, tab: nil, repo: nil),
            effective: TintPayload(PaneTint(stops: [.named(.green)])),
            git: nil, status: nil
        )
        let data = try ControlResponse.info(info).encoded()
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["surface_id"] as? String == "M1")
        #expect(parsed?["tab_name_is_override"] as? Bool == false)
    }
}
