from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
ROOT=Path(__file__).resolve().parent
class ReviewHandler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(ROOT),**kwargs)
    def do_GET(self):
        if self.path.startswith('/admin/'): self.path='/index.html'
        super().do_GET()
ThreadingHTTPServer(('127.0.0.1',8770),ReviewHandler).serve_forever()
