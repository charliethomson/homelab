docker compose \
	-p media \
	--env-file .env \
	-f ./docker-compose.yml $@
