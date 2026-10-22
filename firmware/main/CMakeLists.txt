idf_component_register(SRCS "main.c" "distance_protocol.c"
    INCLUDE_DIRS "." REQUIRES bt nvs_flash esp_timer vl53l1x)
