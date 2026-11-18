#!/usr/bin/env python3

import asyncio
import csv
import logging
import os
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

import aiohttp
from nio import (
    AsyncClient,
    LoginError,
    RoomCreateError,
    RoomVisibility,
)


@dataclass(frozen=True)
class User:
    username: str
    password: str
    display_name: str | None = None


SCRIPT_DIR = Path(__file__).resolve().parent
USERS_CSV = Path(os.environ.get("MATRIX_USERS_CSV", SCRIPT_DIR / "users.csv"))


def load_users(csv_path: Path) -> dict[str, User]:
    users: dict[str, User] = {}
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            display_name = row.get("display_name", "").strip() or None
            users[row["username"]] = User(
                username=row["username"],
                password=row["password"],
                display_name=display_name,
            )
    return users


USERS: dict[str, User] = load_users(USERS_CSV)

SERVER = os.environ.get("MATRIX_SERVER", "http://localhost:8008").rstrip("/")
ROOM_NAME = os.environ.get("MATRIX_ROOM_NAME", "Mactrix Quality Assurance")
ROOM_ALIAS = os.environ.get("MATRIX_ROOM_ALIAS", "mactrix-qa")
SERVER_NAME = os.environ.get("MATRIX_SERVER_NAME", "localhost")
TIMEOUT = int(os.environ.get("MATRIX_TIMEOUT", "60"))


@contextmanager
def _quiet_nio_user_id_warning():
    """Suppress matrix-nio's schema-validation warning for M_NOT_FOUND login responses.

    When Continuwuity hasn't finished creating the account yet, the login response
    is a Matrix error that matrix-nio first tries to validate as a successful
    LoginResponse. That produces a noisy "'user_id' is a required property" warning.
    """
    logger = logging.getLogger("nio.responses")
    filt = logging.Filter()

    def _filter(record: logging.LogRecord) -> bool:
        return "'user_id' is a required property" not in record.getMessage()

    filt.filter = _filter
    logger.addFilter(filt)
    try:
        yield
    finally:
        logger.removeFilter(filt)


async def wait_for_server(session: aiohttp.ClientSession, timeout: int = TIMEOUT) -> None:
    url = f"{SERVER}/_matrix/client/versions"
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=2)) as resp:
                if resp.status == 200:
                    print(f"[ok] connected to server {SERVER}")
                    return
        except Exception as exc:
            print(f"[wait] server not ready yet: {exc}")
        await asyncio.sleep(1)
    raise TimeoutError(f"server did not become available within {timeout}s")


async def login_user(localpart: str, password: str) -> AsyncClient:
    """Log in a user, retrying while the server is still creating accounts."""
    deadline = time.time() + TIMEOUT
    last_error: LoginError | None = None

    while time.time() < deadline:
        client = AsyncClient(SERVER, localpart)
        with _quiet_nio_user_id_warning():
            resp = await client.login(password)
        if getattr(resp, "access_token", None):
            print(f"[ok] user {localpart} signed in")
            return client

        await client.close()

        if isinstance(resp, LoginError) and resp.status_code == "M_NOT_FOUND":
            last_error = resp
            print(f"[wait] user {localpart} not ready yet: {resp}")
            await asyncio.sleep(1)
            continue

        raise RuntimeError(f"login failed for {localpart}: {resp}")

    raise RuntimeError(f"login failed for {localpart}: {last_error}")


async def get_or_create_room(
    session: aiohttp.ClientSession,
    client: AsyncClient,
    name: str,
    topic: str,
    alias: str,
    visibility: RoomVisibility = RoomVisibility.public,
) -> str:
    """Create the room or reuse it if the alias already exists."""
    room_alias = f"#{alias}:{SERVER_NAME}"
    encoded_alias = aiohttp.helpers.quote(room_alias, safe="")
    resolve_url = f"{SERVER}/_matrix/client/v3/directory/room/{encoded_alias}"
    async with session.get(resolve_url) as resolve_resp_http:
        if resolve_resp_http.status == 200:
            resolve_data = await resolve_resp_http.json()
            room_id = resolve_data["room_id"]
            print(f"[ok] using existing room {room_id}")
            return room_id

    create_resp = await client.room_create(
        name=name,
        topic=topic,
        visibility=visibility,
        alias=alias,
    )

    if hasattr(create_resp, "room_id"):
        print(f"[ok] room {create_resp.room_id} created")
        return create_resp.room_id

    if isinstance(create_resp, RoomCreateError):
        raise RuntimeError(f"failed to create room: {create_resp.message}")

    raise RuntimeError(f"unexpected room_create response: {create_resp}")


async def send_message(client: AsyncClient, room_id: str, body: str) -> None:
    await client.room_send(
        room_id,
        message_type="m.room.message",
        content={"msgtype": "m.text", "body": body},
    )
    print(f"[ok] {client.user_id} sent message in room {room_id}: {body}")


async def main() -> int:
    async with aiohttp.ClientSession() as session:
        await wait_for_server(session)

        alice = await login_user(USERS["alice"].username, USERS["alice"].password)
        try:
            if USERS["alice"].display_name:
                await alice.set_displayname(USERS["alice"].display_name)

            room_id = await get_or_create_room(
                session,
                alice,
                name=ROOM_NAME,
                topic="Quality assurance room for Mactrix",
                visibility=RoomVisibility.public,
                alias=ROOM_ALIAS,
            )

            await send_message(alice, room_id, "Welcome to the room!")

            bob = await login_user(USERS["bob"].username, USERS["bob"].password)
            try:
                if USERS["bob"].display_name:
                    await bob.set_displayname(USERS["bob"].display_name)

                # Bob joins the room
                # matrix-nio sends an empty body for join, which Continuwuity rejects
                # with M_BAD_JSON; send an explicit empty JSON object instead.
                join_url = (
                    f"{SERVER}/_matrix/client/v3/rooms/"
                    f"{room_id}/join?access_token={bob.access_token}"
                )
                async with session.post(join_url, json={}) as join_resp_http:
                    join_data = await join_resp_http.json()
                    if join_resp_http.status != 200:
                        raise RuntimeError(f"bob failed to join room: {join_data}")

                await send_message(bob, room_id, "Hello!")
            finally:
                await bob.close()
        finally:
            await alice.close()

    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(1)
