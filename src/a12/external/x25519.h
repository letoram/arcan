void x25519_private_key(uint8_t secret[static 32]);

void x25519_public_key(const uint8_t secret[static 32], uint8_t public[static 32]);

int x25519_shared_secret(
	uint8_t secret_out[static 32],
	const uint8_t secret [static 32],
	const uint8_t ext_pub [static 32]);
