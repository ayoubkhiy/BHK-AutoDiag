from urllib.parse import urlsplit

from django.conf import settings
from django.http import HttpResponse
from django.utils.cache import patch_vary_headers


class ApiCorsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        origin = request.headers.get('Origin', '')
        if not request.path.startswith('/api/') or not self._is_allowed(origin):
            return self.get_response(request)

        if request.method == 'OPTIONS':
            response = HttpResponse(status=204)
        else:
            response = self.get_response(request)
        response['Access-Control-Allow-Origin'] = origin
        response['Access-Control-Allow-Methods'] = 'GET, POST, PATCH, PUT, OPTIONS'
        response['Access-Control-Allow-Headers'] = 'Accept, Authorization, Content-Type'
        response['Access-Control-Max-Age'] = '600'
        patch_vary_headers(response, ('Origin',))
        return response

    @staticmethod
    def _is_allowed(origin):
        if origin in settings.CORS_ALLOWED_ORIGINS:
            return True
        parsed = urlsplit(origin)
        return (
            settings.DEBUG
            and parsed.scheme == 'http'
            and parsed.hostname in {'localhost', '127.0.0.1'}
        )
