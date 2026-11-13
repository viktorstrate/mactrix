#!/usr/bin/env python3

import asyncio
import csv
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import aiohttp
from nio import AsyncClient, RoomVisibility


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
    client = AsyncClient(SERVER, localpart)
    resp = await client.login(password)
    if not getattr(resp, "access_token", None):
        raise RuntimeError(f"login failed for {localpart}: {resp}")
    print(f"[ok] user {localpart} signed in")
    return client


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
        if USERS["alice"].display_name:
            await alice.set_displayname(USERS["alice"].display_name)

        create_resp = await alice.room_create(
            name=ROOM_NAME,
            topic="Quality assurance room for Mactrix",
            visibility=RoomVisibility.public,
            alias=ROOM_ALIAS,
        )
        room_id = create_resp.room_id
        print(f"[ok] room {room_id} created")

        await send_message(alice, room_id, "Welcome to the room!")

        bob = await login_user(USERS["bob"].username, USERS["bob"].password)
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

        await alice.close()
        await bob.close()

    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except Exception as exc:
        print(f"[error] {exc}", file=sys.stderr)
        sys.exit(1)
