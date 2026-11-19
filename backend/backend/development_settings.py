"""Local development settings; WSGI deployments use backend.settings directly."""

import os

os.environ.setdefault('DJANGO_DEBUG', 'true')

from .settings import *
