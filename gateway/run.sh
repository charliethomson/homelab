docker compose \
	-p gateway \
	--env-file .env \
	-f ./docker-compose.yml $@
