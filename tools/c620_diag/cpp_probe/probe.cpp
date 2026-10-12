#include <cstdio>
#include <cstdint>
#include "dmcan.h"
int main(){
  dmcan_context* ctx=nullptr; dmcan_context_create(&ctx);
  if(!ctx){puts("context=null"); return 2;}
  dmcan_print_version(ctx);
  int n=dmcan_find_devices(ctx); printf("count=%d\n",n); dmcan_show_all_devices(ctx);
  dmcan_device_handle* dev=nullptr;
  if(!dmcan_device_get(ctx,&dev,0)){puts("get=false"); dmcan_context_destroy(ctx); return 3;}
  bool op=dmcan_device_open(dev); printf("open=%d\n",(int)op);
  bool en=dmcan_device_enable_channel(dev,0); printf("enable=%d\n",(int)en);
  dmcan_channel_can_info_t info{}; bool gr=dmcan_device_get_channel_baudrate(dev,0,&info);
  printf("get_baud=%d fd=%d nominal=%u data=%u\n",(int)gr,(int)info.canfd,info.can_baudrate,info.canfd_baudrate);
  if(op) dmcan_device_close(dev); dmcan_context_destroy(ctx); return en?0:4;
}
