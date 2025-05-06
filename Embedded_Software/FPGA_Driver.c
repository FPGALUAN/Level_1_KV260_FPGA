// Created by: PHAM HOAI LUAN
// Created on: 2025-05-06
// Description: FPGA driver functions to interact with DMA and CGRA (ZDMA-based)

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <dirent.h>

#define DMA_BASE_PHYS	 0x00000000fd500000LL
#define DMA_MMAP_SIZE	 0x0000000000010000LL
#define REG_BASE_PHYS	 0x00000000A0000000LL
#define REG_MMAP_SIZE	 0x0000000010000000LL
#define LMM_BASE_PHYS	 0x00000000A0000000LL
#define DDR_BASE_PHYS	 0x0000000800000000LL
#define DDR_MMAP_SIZE	 0x0000000080000000LL

typedef uint64_t U64;
typedef uint32_t U32;
typedef uint16_t U16;

struct dma_ctrl {
  U32 ZDMA_ERR_CTRL;
  U32 dmy0[63];
  U32 ZDMA_CH_ISR;
  U32 ZDMA_CH_IMR;
  U32 ZDMA_CH_IEN;
  U32 ZDMA_CH_IDS;
  U32 ZDMA_CH_CTRL0;
  U32 ZDMA_CH_CTRL1;
  U32 ZDMA_CH_FCI;
  U32 ZDMA_CH_STATUS;
  U32 ZDMA_CH_DATA_ATTR;
  U32 ZDMA_CH_DSCR_ATTR;
  U32 ZDMA_CH_SRC_DSCR_WORD0;
  U32 ZDMA_CH_SRC_DSCR_WORD1;
  U32 ZDMA_CH_SRC_DSCR_WORD2;
  U32 ZDMA_CH_SRC_DSCR_WORD3;
  U32 ZDMA_CH_DST_DSCR_WORD0;
  U32 ZDMA_CH_DST_DSCR_WORD1;
  U32 ZDMA_CH_DST_DSCR_WORD2;
  U32 ZDMA_CH_DST_DSCR_WORD3;
  U32 ZDMA_CH_WR_ONLY_WORD0;
  U32 ZDMA_CH_WR_ONLY_WORD1;
  U32 ZDMA_CH_WR_ONLY_WORD2;
  U32 ZDMA_CH_WR_ONLY_WORD3;
  U32 ZDMA_CH_SRC_START_LSB;
  U32 ZDMA_CH_SRC_START_MSB;
  U32 ZDMA_CH_DST_START_LSB;
  U32 ZDMA_CH_DST_START_MSB;
  U32 dmy1[9];
  U32 ZDMA_CH_RATE_CTRL;
  U32 ZDMA_CH_IRQ_SRC_ACCT;
  U32 ZDMA_CH_IRQ_DST_ACCT;
  U32 dmy2[26];
  U32 ZDMA_CH_CTRL2;
};

struct {
  U64 dma_phys;
  U64 dma_mmap;
  U32 *pio_32_mmap;
  U64 lmm_phys;
  U64 lmm_mmap;
  U64 ddr_phys;
  U64 ddr_mmap;
} MY_IP_info;

struct {
  volatile U64 dma_ctrl;
} fpga;

static int filter(const struct dirent *dir) {
  return dir->d_name[0] != '.';
}

static void trim(char *d_name) {
  char *p = strchr(d_name, '\n');
  if (p) *p = '\0';
}

static int is_target_dev(char *d_name, const char *target) {
  char path[64], name[64];
  FILE *fp;
  snprintf(path, sizeof(path), "/sys/class/uio/%s/name", d_name);
  if ((fp = fopen(path, "r")) == NULL) return 0;
  if (fgets(name, sizeof(name), fp) == NULL) {
    fclose(fp);
    return 0;
  }
  fclose(fp);
  return strcmp(name, target) == 0;
}

static int get_reg_size(char *d_name) {
  char path[64], size[32];
  FILE *fp;
  snprintf(path, sizeof(path), "/sys/class/uio/%s/maps/map0/size", d_name);
  if ((fp = fopen(path, "r")) == NULL) return 0;
  if (fgets(size, sizeof(size), fp) == NULL) {
    fclose(fp);
    return 0;
  }
  fclose(fp);
  return strtoull(size, NULL, 16);
}

int fpga_open()
{
  struct dirent **namelist;
  int num_dirs, dir;
  int reg_size;
  int  fd_dma_found = 0;
  char path[1024];
  int  fd_dma;
  int  fd_reg;
  int  fd_ddr;
  char *UIO_DMA           = "dma-controller\n";
  char *UIO_AXI_CGRA     = "MY_IP\n";
  char *UIO_DDR_HIGH      = "ddr_high\n";
  
  // Scan the directory
  if ((num_dirs = scandir("/sys/class/uio", &namelist, filter, alphasort)) == -1)
    return -1;

  // Browse for each directory
  for (dir = 0; dir < num_dirs; ++dir) {
    trim(namelist[dir]->d_name); // Remove '\n'
    // Check the target device is dma-controller
    if (!fd_dma_found && is_target_dev(namelist[dir]->d_name, UIO_DMA) && (reg_size = get_reg_size(namelist[dir]->d_name))) {
      // If the target device is not CGRA, then continue
      if (strlen(namelist[dir]->d_name)>4) /* ignore /dev/uio1X */
	    continue;
      sprintf(path, "/dev/%s", namelist[dir]->d_name);  // assign path = /dev/uio4:dma-controller
      free(namelist[dir]);
      if ((fd_dma = open(path, O_RDWR | O_SYNC)) == -1) // open /dev/uio4:dma-controller for read and write 
	    continue;
      printf("%s: %s", path, UIO_DMA);
      MY_IP_info.dma_phys = DMA_BASE_PHYS; // 0x00000000fd500000LL Assign the physical address of DMA
      MY_IP_info.dma_mmap = (U64)mmap(NULL, reg_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd_dma, 0); // mmap(cache-on)  4KB aligned
      close(fd_dma);
      if (MY_IP_info.dma_mmap == (U64)(uintptr_t)MAP_FAILED)
	    continue;
      fd_dma_found++;
    }
    // Check the target device is CGRA
    else if (is_target_dev(namelist[dir]->d_name, UIO_AXI_CGRA)) {
      sprintf(path, "/dev/%s", namelist[dir]->d_name);
      free(namelist[dir]);
      if ((fd_reg = open(path, O_RDWR | O_SYNC)) == -1) {
	printf("open failed. %s", UIO_AXI_CGRA);
	return -1;
      }
      printf("%s: %s", path, UIO_AXI_CGRA);
      
      MY_IP_info.pio_32_mmap = (U32*)mmap(NULL, REG_MMAP_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd_reg, 0); /* 4GB */
      if (MY_IP_info.pio_32_mmap == MAP_FAILED) {
		printf("pio_32_mmap failed. errno=%d\n", errno);
		return -1;
      }
	
      MY_IP_info.lmm_phys = LMM_BASE_PHYS;
      MY_IP_info.lmm_mmap = (LMM_BASE_PHYS - REG_BASE_PHYS);
    }
    else if (is_target_dev(namelist[dir]->d_name, UIO_DDR_HIGH)) {
      sprintf(path, "/dev/%s", namelist[dir]->d_name);
      free(namelist[dir]);
      if ((fd_ddr = open(path, O_RDWR | O_SYNC)) == -1) {
	printf("open failed. %s",UIO_DDR_HIGH);
	return -1;
      }
      printf("%s: %s", path, UIO_DDR_HIGH);
      // mmap(cache-on)  4KB aligned
      MY_IP_info.ddr_phys = DDR_BASE_PHYS;
      MY_IP_info.ddr_mmap = (U64)mmap(NULL, DDR_MMAP_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd_ddr, 0); /* 2GB */
      if ((void*)MY_IP_info.ddr_mmap == MAP_FAILED) {
	printf("fd_ddr mmap() failed. errno=%d\n", errno);
	return -1;
      }
    }
    else {
      free(namelist[dir]);
      continue;
    }
  }
  free(namelist);

  if (fd_dma_found) {
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_ERR_CTRL          = 0x00000001;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_ISR            = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_IMR            = 0x00000FFF;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_IEN            = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_IDS            = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_CTRL0          = 0x00000080;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_CTRL1          = 0x000003FF;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_FCI            = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_STATUS         = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DATA_ATTR      = 0x04C3D30F; /* Note - AxCACHE: 0011 value recomended by Xilinx. */
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DSCR_ATTR      = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_SRC_DSCR_WORD0 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_SRC_DSCR_WORD1 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_SRC_DSCR_WORD2 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_SRC_DSCR_WORD3 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DST_DSCR_WORD0 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DST_DSCR_WORD1 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DST_DSCR_WORD2 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DST_DSCR_WORD3 = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_WR_ONLY_WORD0  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_WR_ONLY_WORD1  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_WR_ONLY_WORD2  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_WR_ONLY_WORD3  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_SRC_START_LSB  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_SRC_START_MSB  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DST_START_LSB  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_DST_START_MSB  = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_RATE_CTRL      = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_IRQ_SRC_ACCT   = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_IRQ_DST_ACCT   = 0x00000000;
    ((struct dma_ctrl*)MY_IP_info.dma_mmap)->ZDMA_CH_CTRL2          = 0x00000000;
  }
  return (1);
}

void dma_write(U64 Offset, U64 size) {
  int status;
  *(U64*)&((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_SRC_DSCR_WORD0 = DDR_BASE_PHYS + Offset;
  ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_SRC_DSCR_WORD2 = size * sizeof(U16);
  *(U64*)&((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_DST_DSCR_WORD0 = LMM_BASE_PHYS + Offset;
  ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_DST_DSCR_WORD2 = size * sizeof(U16);
  ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_CTRL2 = 1;
  do {
    status = ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_STATUS & 3;
  } while (status != 0 && status != 3);
}

void dma_read(U64 Offset, U64 size) {
  int status;
  *(U64*)&((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_SRC_DSCR_WORD0 = LMM_BASE_PHYS + Offset;
  ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_SRC_DSCR_WORD2 = size * sizeof(U16);
  *(U64*)&((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_DST_DSCR_WORD0 = DDR_BASE_PHYS + Offset;
  ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_DST_DSCR_WORD2 = size * sizeof(U16);
  ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_CTRL2 = 1;
  do {
    status = ((struct dma_ctrl*)fpga.dma_ctrl)->ZDMA_CH_STATUS & 3;
  } while (status != 0 && status != 3);
}
