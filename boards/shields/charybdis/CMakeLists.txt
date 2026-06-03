if(CONFIG_ZMK_AUTO_MOUSE_LAYER OR CONFIG_ZMK_LANG_SWITCH_FREEZE)
  zephyr_library()
  zephyr_library_include_directories(${APPLICATION_SOURCE_DIR}/include)

  if(CONFIG_ZMK_AUTO_MOUSE_LAYER)
    zephyr_library_sources(
      ${CMAKE_CURRENT_LIST_DIR}/../../../zmk_extra_modules/auto_mouse_layer/src/auto_mouse_layer.c
    )
  endif()

  if(CONFIG_ZMK_LANG_SWITCH_FREEZE)
    zephyr_library_sources(
      ${CMAKE_CURRENT_LIST_DIR}/../../../zmk_extra_modules/lang_switch_freeze/src/lang_switch_freeze.c
    )
  endif()
endif()
