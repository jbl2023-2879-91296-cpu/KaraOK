import secrets


def generate_database_password() -> str:
    return f"KaraOK!2026-{secrets.token_hex(24)}"


def generate_jwt_secret() -> str:
    return secrets.token_urlsafe(64)


if __name__ == "__main__":
    print("Database password:")
    print(generate_database_password())

    print("\nJWT secret:")
    print(generate_jwt_secret())