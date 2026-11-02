#include "face_rpc.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void){
 uint8_t q[20]={'N','F','C','1',0,0,0,1,0,0,0,1,0,0,0,7,0,0,0,0},out[256],result[224];
 uint32_t status[FACE_STATUS_WORDS]={0};status[0]=1;status[22]=0x12345678;
 memset(result,0xa5,sizeof(result));
 size_t n=face_rpc_handle(q,20,5,status,result,224,5,9,out);
 assert(n==112&&!memcmp(out,"NFS1",4)&&out[15]==7&&!out[19]&&out[23]==1&&out[111]==0x78);
 assert(face_rpc_handle(q,19,5,status,result,224,5,9,out)==0);
 q[11]=2;q[19]=9;
 n=face_rpc_handle(q,20,5,status,result,224,5,9,out);assert(n==244&&!out[19]&&!memcmp(out+20,result,224));
 n=face_rpc_handle(q,20,6,status,result,224,5,9,out);assert(n==20&&out[19]==3);
 q[19]=8;n=face_rpc_handle(q,20,5,status,result,224,5,9,out);assert(n==20&&out[19]==4);
 n=face_rpc_handle(q,20,5,status,result,0,5,9,out);assert(n==20&&out[19]==2);
 q[7]=2;n=face_rpc_handle(q,20,5,status,result,224,5,9,out);assert(n==20&&out[19]==1);
 puts("FACE_RPC_STATUS_RESULT_OWNER_BOUNDS_PASS");return 0;
}
