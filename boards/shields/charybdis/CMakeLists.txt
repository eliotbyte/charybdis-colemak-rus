if(CONFIG_ZMK_AUTO_MOUSE_LAYER)
  zephyr_library()
  zephyr_library_sources(
    ${CMAKE_CURRENT_LIST_DIR}/../../../zmk_extra_modules/auto_mouse_layer/src/auto_mouse_layer.c
  )
  zephyr_library_include_directories(${APPLICATION_SOURCE_DIR}/include)
endif()
