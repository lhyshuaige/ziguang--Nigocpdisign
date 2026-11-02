#ifndef FLASH_BOOT_SERVICE_H
#define FLASH_BOOT_SERVICE_H
#include "loader.h"
size_t flash_install_request(ngb_loader *,uint32_t,uint16_t,const uint8_t *,size_t,uint8_t *);
#endif
