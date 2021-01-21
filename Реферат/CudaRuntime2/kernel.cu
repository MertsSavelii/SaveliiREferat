#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <stdio.h>
#include <string.h>
#include <malloc.h>
#include <stdint.h>

 struct pix {
    uint8_t R = 0;
    uint8_t G = 0;
    uint8_t B = 0;
};
 struct BMPHeader {
    uint8_t n1;//1
    uint8_t n2;//1
    uint32_t Size;//4
    uint16_t Reserved1;//2
    uint16_t Reserved2;//2
    uint32_t OffsetBits;//4
    uint32_t Size2;//4
    uint32_t Width;//4
    uint32_t Height;//4
    uint16_t Planes;//2
    uint16_t BytePerPix;//2
    uint32_t Compression;//4
    uint32_t SizeImage;//4
    uint32_t XpelsPerMeter;//4
    uint32_t YpelsPerMeter;//4
    uint32_t ColorsUsed;//4
    uint32_t ColorsImportant;//4
};

__global__ void addminor(pix* img, int32_t* height, int32_t* width)
{
    int sumR = 0;
    int sumG = 0;
    int sumB = 0;
    int count = 0;
    int ii = blockIdx.x;//текущий пиксель высота
    int jj = threadIdx.x;//текущий пиксель ширина
    for (int i = ii - 1; i <= ii + 1; i++) {//высота
        for (int j = jj - 1; j <= jj + 1; j++) {//ширина
            if (i >= 0 && i < *height && j >= 0 && j < *width) {//не выходим за границы массива
                sumR += img[i * *width + j].R;
                sumG += img[i * *width + j].G;
                sumB += img[i * *width + j].B;
                count++;
            }
        }
    }
    sumR /= count;
    sumG /= count;
    sumB /= count;
    img[ii * *width + jj].R = sumR;
    img[ii * *width + jj].G = sumG;
    img[ii * *width + jj].B = sumB;
}


__host__ int StartCuda(pix* img, int32_t height, int32_t width, int32_t BytePerPix) {
    int32_t* dev_width;
    cudaMalloc((void**)&dev_width, sizeof(int32_t));
    cudaMemcpy(dev_width, &width, sizeof(int32_t), cudaMemcpyHostToDevice);

    int32_t* dev_height;
    cudaMalloc((void**)&dev_height, sizeof(int32_t));
    cudaMemcpy(dev_height, &height, sizeof(int32_t), cudaMemcpyHostToDevice);

    pix* dev_img;
    cudaMalloc((void**)&dev_img, width * height * BytePerPix);
    cudaMemcpy(dev_img, img, width * height * BytePerPix, cudaMemcpyHostToDevice);

    addminor <<< height, width >>> (dev_img, dev_height, dev_width);

    cudaMemcpy(img, dev_img, width * height * BytePerPix, cudaMemcpyDeviceToHost);

    cudaFree(dev_width);
    cudaFree(dev_height);
    cudaFree(dev_img);
    
    return 0;
}

__host__ int MakeBMP(pix* img, FILE* file, int32_t width, int32_t height, int32_t BytePerPix)
{
    struct BMPHeader BmpH;
    fseek(file, SEEK_SET, SEEK_SET);
    fread(&BmpH, sizeof(BMPHeader), 1, file);

    FILE* file2;
    file2 = fopen("1mod.bmp", "wb");
    fwrite(&BmpH, sizeof(BMPHeader), 1, file2);


    int LineLenght = (width * BytePerPix + BytePerPix) / 4 * 4;
    uint8_t* arr = (uint8_t*)calloc(height * LineLenght, 1);
    for (int i = 0, int ii = 0; i < width * height; i++) {
        if (i % width  == 0 && i != 0) {
            for (int j = 0; j < (LineLenght - width * BytePerPix); j++) {//здесь дополнял строку нулями
                arr[ii] = 0;
                ii++;
            }
        }
        
        arr[ii] = img[i].R;
        ii++;
        arr[ii] = img[i].G;
        ii++;
        arr[ii] = img[i].B;
        ii++;
        //printf("\n current ii is %d ", ii);
    }
    fseek(file2, 54, SEEK_SET);
    printf("\n");
    for (int i = 0; i < height * LineLenght; i++) {
        //printf("%3d ", arr[i]);
        
        fwrite(&arr[i], 1, sizeof(arr[i]), file2);
    }

    fclose(file2);
    free(arr);
    return 0;
}

__host__ int main()
{
    FILE* file;
    file = fopen("1.bmp", "rb");

    //check that the BMP file
    char name1, name2;//B M
    fread(&name1, 1, 1, file);
    fread(&name2, 1, 1, file);
    if (name1 != 'B' && name2 != 'm') {
        printf("Incorrect file format\n");
        return 0;
    }

    //looking at the image dimensions
    int32_t width; // Ширина изображения (4 байта)
    fseek(file, 18, SEEK_SET);
    fread(&width, 4, 1, file);

    int32_t height; // Высота изображения (4 байта)
    fseek(file, 22, SEEK_SET);
    fread(&height, 4, 1, file);

    int32_t BytePerPix;
    fseek(file, 28, SEEK_SET);
    fread(&BytePerPix, 4, 1, file);
    BytePerPix = BytePerPix / 8;

    int LineLenght = (width * BytePerPix + BytePerPix) / 4 * 4;

    //ссчитываем изображение, на каждый пиксель будет уходить BitPerPix / 8 байт.
    struct pix* img = (pix*)calloc(width * height, 3);//new pix [width * height * BytePerPix + width * BytePerPix % 4];
    //в бмп есть выравнивание, если строка пикселей состоит не из кратного 4 числа пикселей то её дополняют 0
    for (int i = 0; i < height; i++) {
        for (int j = 0; j < width; j++) {
            fseek(file, 54 + i * LineLenght + j * BytePerPix, SEEK_SET);
            fread(&img[i * width + j].R, 1, 1, file);
            fseek(file, 54 + i * LineLenght + j * BytePerPix + 1, SEEK_SET);
            fread(&img[i * width + j].G, 1, 1, file);
            fseek(file, 54 + i * LineLenght + j * BytePerPix + 2, SEEK_SET);
            fread(&img[i * width + j].B, 1, 1, file);
        }
    }
    
    //printf("LineLenght %d , width %d , height %d , BytePerPix %d\n", LineLenght, width, height, BytePerPix);
    
    StartCuda(img, height, width, BytePerPix);

    MakeBMP(img, file, width, height, BytePerPix);

    free(img);
    fclose(file);
    return 0;
}