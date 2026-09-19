import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String:String]
    var body: Data
}

final class TinyHTTPServer: @unchecked Sendable {
    let port: UInt16
    let engine: ModelEngine

    init(port: UInt16, engine: ModelEngine) { self.port = port; self.engine = engine }

    func run() throws {
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { throw NSError(domain: "socket", code: 1) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 32) == 0 else { close(fd); throw NSError(domain: "bind/listen", code: 2) }
        print("SwiftTinyLLM dashboard: http://127.0.0.1:\(port)")
        while true {
            var clientAddr = sockaddr(); var len = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(fd, &clientAddr, &len)
            if client < 0 { continue }
            Task.detached { [engine] in
                defer { close(client) }
                guard let request = Self.readRequest(client) else { return }
                let response = await Self.route(request, engine: engine)
                Self.send(client, response)
            }
        }
    }

    static func readRequest(_ fd: Int32) -> HTTPRequest? {
        var data = Data(); var buf = [UInt8](repeating: 0, count: 8192)
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil && data.count < 1_048_576 {
            let n = recv(fd, &buf, buf.count, 0); if n <= 0 { return nil }
            data.append(buf, count: n)
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
        }
        guard let end = headerEnd else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " "); guard parts.count >= 2 else { return nil }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        let bodyStart = end.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        while data.count - bodyStart < contentLength {
            let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; data.append(buf, count: n)
        }
        let available = min(contentLength, data.count - bodyStart)
        let body = available > 0 ? data.subdata(in: bodyStart..<(bodyStart + available)) : Data()
        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: body)
    }

    static func route(_ req: HTTPRequest, engine: ModelEngine) async -> (Int,String,Data) {
        if req.method == "GET" && req.path == "/" { return (200, "text/html; charset=utf-8", Data(dashboard.utf8)) }
        if req.method == "GET" && req.path == "/api/info" {
            let info = await engine.info(); let data = (try? JSONEncoder().encode(info)) ?? Data("{}".utf8)
            return (200, "application/json", data)
        }
        if req.method == "POST" && req.path == "/api/generate" {
            guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String:Any] else { return (400,"application/json",Data("{\"error\":\"bad json\"}".utf8)) }
            let prompt = json["prompt"] as? String ?? ""
            let maxTokens = json["maxTokens"] as? Int ?? 64
            let temp = Float(json["temperature"] as? Double ?? 0.8)
            let topK = json["topK"] as? Int ?? 40
            let topP = Float(json["topP"] as? Double ?? 0.95)
            let seed = UInt64(json["seed"] as? Int ?? 42)
            let text = await engine.generate(prompt: prompt, maxTokens: maxTokens, temperature: temp, topK: topK, topP: topP, seed: seed)
            let data = (try? JSONSerialization.data(withJSONObject: ["text": text])) ?? Data("{}".utf8)
            return (200,"application/json",data)
        }
        return (404,"text/plain",Data("not found".utf8))
    }

    static func send(_ fd: Int32, _ response: (Int,String,Data)) {
        let reason = response.0 == 200 ? "OK" : response.0 == 400 ? "Bad Request" : "Not Found"
        let head = "HTTP/1.1 \(response.0) \(reason)\r\nContent-Type: \(response.1)\r\nContent-Length: \(response.2.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        var packet = Data(head.utf8); packet.append(response.2)
        packet.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let n = DarwinOrGlibcSend(fd, p, remaining)
                if n <= 0 { break }; remaining -= n; p = p.advanced(by: n)
            }
        }
    }
}

@inline(__always) private func DarwinOrGlibcSend(_ fd: Int32, _ ptr: UnsafeRawPointer, _ count: Int) -> Int {
    #if os(Linux)
    return Glibc.send(fd, ptr, count, Int32(MSG_NOSIGNAL))
    #else
    return Darwin.send(fd, ptr, count, 0)
    #endif
}

private let dashboard = #"""
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SwiftTinyLLM</title>
<style>
:root{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",system-ui;background:#0b0b0d;color:#f5f5f7}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(circle at 50% -20%,#24242a,#0b0b0d 45%)}main{max-width:1080px;margin:auto;padding:36px 20px}.bar{display:flex;justify-content:space-between;align-items:center;margin-bottom:24px}.brand{font-weight:700;font-size:24px}.pill{border:1px solid #34343a;border-radius:999px;padding:7px 12px;color:#a1a1a6}.grid{display:grid;grid-template-columns:1fr 320px;gap:18px}.panel{background:rgba(29,29,31,.78);border:1px solid #333337;border-radius:22px;box-shadow:0 18px 55px #0008;backdrop-filter:blur(24px)}.chat{min-height:660px;display:flex;flex-direction:column}.messages{padding:22px;flex:1;white-space:pre-wrap;overflow:auto}.bubble{padding:14px 16px;border-radius:18px;margin:8px 0;line-height:1.45}.user{background:#2c2c30;margin-left:18%}.model{background:#161618;margin-right:18%;border:1px solid #2e2e32}.composer{padding:16px;border-top:1px solid #303034}textarea{width:100%;min-height:94px;border:0;resize:vertical;border-radius:16px;background:#111113;color:white;padding:14px;font:inherit;outline:none}.row{display:flex;gap:10px;margin-top:10px}button{border:0;border-radius:13px;background:#2997ff;color:#fff;padding:11px 18px;font-weight:650;cursor:pointer}button:disabled{opacity:.45}.side{padding:20px}.metric{border-bottom:1px solid #303034;padding:12px 0}.metric b{display:block;font-size:21px;margin-top:5px}label{display:block;margin:18px 0 5px;color:#a1a1a6;font-size:13px}input{width:100%}code{font-family:"SF Mono",ui-monospace,monospace;color:#7dd3fc}@media(max-width:800px){.grid{grid-template-columns:1fr}.chat{min-height:580px}}
</style></head><body><main><div class="bar"><div class="brand">SwiftTinyLLM</div><div class="pill">native Swift transformer</div></div><div class="grid"><section class="panel chat"><div id="messages" class="messages"><div class="bubble model">Model runtime online. This is the locally compiled transformer, not a remote inference API.</div></div><div class="composer"><textarea id="prompt" placeholder="Message the model…"></textarea><div class="row"><button id="go">Generate</button><span id="status" class="pill">idle</span></div></div></section><aside class="panel side"><h3>Runtime</h3><div class="metric">Parameters<b id="params">—</b></div><div class="metric">Architecture<b id="arch">—</b></div><div class="metric">Context<b id="ctx">—</b></div><label>Temperature <span id="tv">0.80</span></label><input id="temp" type="range" min="0" max="1.5" value="0.8" step="0.05"><label>Top K <span id="kv">40</span></label><input id="topk" type="range" min="1" max="128" value="40"><label>Top P <span id="pv">0.95</span></label><input id="topp" type="range" min="0.05" max="1" value="0.95" step="0.05"><label>Max new tokens</label><input id="max" type="number" value="80" min="1" max="512"><p style="color:#86868b;margin-top:24px">Tokenizer: <code>UTF-8 byte + BOS/EOS</code><br>Attention: <code>causal MHA + RoPE</code><br>MLP: <code>SwiGLU</code><br>Norm: <code>RMSNorm</code></p></aside></div></main>
<script>
const $=id=>document.getElementById(id), msgs=$('messages'),go=$('go');
for(const [id,out] of [['temp','tv'],['topk','kv'],['topp','pv']]) $(id).oninput=()=>$(out).textContent=$(id).value;
fetch('/api/info').then(r=>r.json()).then(x=>{ $('params').textContent=x.parameters.toLocaleString(); $('arch').textContent=`${x.layers}L × ${x.dModel}d × ${x.heads}H`; $('ctx').textContent=x.context+' tokens'; });
function bubble(text,kind){const d=document.createElement('div');d.className='bubble '+kind;d.textContent=text;msgs.appendChild(d);msgs.scrollTop=msgs.scrollHeight}
go.onclick=async()=>{const p=$('prompt').value;if(!p.trim())return;bubble(p,'user');$('prompt').value='';go.disabled=true;$('status').textContent='thinking';try{const r=await fetch('/api/generate',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({prompt:p,maxTokens:+$('max').value,temperature:+$('temp').value,topK:+$('topk').value,topP:+$('topp').value,seed:Date.now()&0x7fffffff})});const x=await r.json();bubble(x.text||'(no output)','model')}catch(e){bubble(String(e),'model')}finally{go.disabled=false;$('status').textContent='idle'}};
</script></body></html>
"""#
