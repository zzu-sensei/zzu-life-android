"""Web API 客户端模块"""

from .eas import StudentWebEASClient
from .network import EPortalClient, SelfServiceSystem, discover_portal_info

__all__ = [
    "EPortalClient",
    "SelfServiceSystem",
    "StudentWebEASClient",
    "discover_portal_info",
]
