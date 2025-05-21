"""
Asynchronous log event subscriber and parser for Aegis protocol events.
"""

import asyncio
from typing import AsyncGenerator, Dict, Any

class EventStream:
    """
    Subscribes to contract event logs and yields structured events to keepers.
    """
    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url
        self._running = False

    async def start(self):
        self._running = True

    async def stop(self):
        self._running = False

    async def subscribe_auction_events(self) -> AsyncGenerator[Dict[str, Any], None]:
        while self._running:
            await asyncio.sleep(1.0)
