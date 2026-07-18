import secrets


def generate_database_password() -> str:
    return f"KaraOK!2026-{secrets.token_hex(24)}"


if __name__ == "__main__":
    print(generate_database_password())