from .logging import logger
from . import logging
from . import aio
from . import app
from . import web
from . import exception
import importlib.metadata

logger.disable(__name__)

try:
    __version__ = importlib.metadata.version(__name__)
except importlib.metadata.PackageNotFoundError:
    # Serverless runtimes may bundle the source tree without installing the
    # project itself, so distribution metadata is not always available.
    __version__ = "0.0.0+source"
__all__ = ["aio", "app", "web", "exception", "logging"]
