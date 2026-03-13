import http.server
import json
import urllib.request
import urllib.error
import time
import os
from http.server import ThreadingHTTPServer

OLLAMA_HOST = "http://127.0.0.1:11434"
PORT = 11435

USAGE_FILE = os.path.expanduser("~/.ollama/ollamabar_usage.json")

def load_usage():
    if os.path.exists(USAGE_FILE):
        try:
            with open(USAGE_FILE, 'r') as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_usage(usage):
    try:
        os.makedirs(os.path.dirname(USAGE_FILE), exist_ok=True)
        with open(USAGE_FILE, 'w') as f:
            json.dump(usage, f)
    except Exception as e:
        print(f"Error saving usage: {e}")

class ProxyHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self._proxy_request("GET")
        
    def do_POST(self):
        self._proxy_request("POST")
        
    def do_OPTIONS(self):
        self._proxy_request("OPTIONS")

    def _proxy_request(self, method):
        url = f"{OLLAMA_HOST}{self.path}"
        headers = {k: v for k, v in self.headers.items() if k.lower() != 'host'}
        data = None
        
        if method == "POST":
            content_length = int(self.headers.get('Content-Length', 0))
            if content_length > 0:
                data = self.rfile.read(content_length)

        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        
        try:
            with urllib.request.urlopen(req) as response:
                self.send_response(response.status)
                for k, v in response.headers.items():
                    self.send_header(k, v)
                self.end_headers()
                
                # Stream the response and intercept json chunks
                prompt_tokens = 0
                eval_tokens = 0
                
                while True:
                    chunk = response.read(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    
                    # try parsing the chunk for tokens
                    lines = chunk.split(b'\n')
                    for line in lines:
                        if not line: continue
                        try:
                            # Usually chunks are full json lines in Ollama
                            obj = json.loads(line)
                            if 'prompt_eval_count' in obj:
                                prompt_tokens = obj['prompt_eval_count']
                            if 'eval_count' in obj:
                                eval_tokens = obj['eval_count']
                        except:
                            pass
                
                # Update usage if tokens found
                if prompt_tokens > 0 or eval_tokens > 0:
                    self._update_usage(prompt_tokens, eval_tokens)

        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            for k, v in e.headers.items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())

    def _update_usage(self, prompt, eval_tokens):
        today = time.strftime("%Y-%m-%d")
        week = time.strftime("%Y-W%W")
        
        usage = load_usage()
        
        if 'daily' not in usage: usage['daily'] = {}
        if 'weekly' not in usage: usage['weekly'] = {}
        if 'total' not in usage: usage['total'] = {'prompt': 0, 'eval': 0}
        
        if today not in usage['daily']: usage['daily'][today] = {'prompt': 0, 'eval': 0}
        if week not in usage['weekly']: usage['weekly'][week] = {'prompt': 0, 'eval': 0}
        
        usage['daily'][today]['prompt'] += prompt
        usage['daily'][today]['eval'] += eval_tokens
        
        usage['weekly'][week]['prompt'] += prompt
        usage['weekly'][week]['eval'] += eval_tokens
        
        usage['total']['prompt'] += prompt
        usage['total']['eval'] += eval_tokens
        
        save_usage(usage)

def run():
    server_address = ('127.0.0.1', PORT)
    httpd = ThreadingHTTPServer(server_address, ProxyHTTPRequestHandler)
    print(f"Ollama Proxy started on port {PORT}...")
    httpd.serve_forever()

if __name__ == '__main__':
    run()
