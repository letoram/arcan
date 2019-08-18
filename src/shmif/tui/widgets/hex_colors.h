/* GIMP header image file format (RGB) */

static const unsigned int width = 256;
static const unsigned int height = 1;

/*  Call this macro repeatedly.  After each use, the pixel data can be extracted  */

#define HEADER_PIXEL(data,pixel) {\
pixel[0] = (((data[0] - 33) << 2) | ((data[1] - 33) >> 4)); \
pixel[1] = ((((data[1] - 33) & 0xF) << 4) | ((data[2] - 33) >> 2)); \
pixel[2] = ((((data[2] - 33) & 0x3) << 6) | ((data[3] - 33))); \
data += 4; \
}
static char *header_data =
	"!!!!SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`"
	"SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`SVL`"
	"E0]!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!`T!!"
	"``Q!``Q!``Q!``Q!``Q!``Q!``Q!``Q!``Q!``Q!`T!!`T!!`T!!`T!!`T!!`T!!"
	"`T!!!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM"
	"!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM!'YM`T!!`T!!`T!!`T!!`T!!"
	"`T!!!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G"
	"!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G!0^G`T!!`T!!`T!!`T!!`Q$3"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`"
	"B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`B!$`````"
	"";
