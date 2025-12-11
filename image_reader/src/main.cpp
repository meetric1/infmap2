#include <string>
#include "GarrysMod/Lua/Interface.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define clamp(x, l, h) (x < l ? l : x > h ? h : x)

struct ImageReader {
	int width;
	int height;
	int stride;
	uint16_t* data;
};

static int IMAGEREADER_METATABLE = 0;
LUA_FUNCTION(IMAGEREADER_ImageReader) {
	LUA->CheckType(1, GarrysMod::Lua::Type::String);

	unsigned int data_size;
	const char* data = LUA->GetString(1, &data_size);
	const auto image_reader = new ImageReader();
	image_reader->data = stbi_load_16_from_memory(
		(const unsigned char*)(data),
		(int)data_size,
		&(image_reader->width),
		&(image_reader->height),
		&(image_reader->stride),
		0
	);

	if (!image_reader->data) {
		char message[] = "Image couldn't be parsed!";
		if (stbi__g_failure_reason) {
			LUA->ThrowError((std::string(message) + " (" + stbi__g_failure_reason + ")").c_str());
		} 
		else {
			LUA->ThrowError(message);
		}
		return 0;
	}

	LUA->PushUserType(image_reader, IMAGEREADER_METATABLE);
	LUA->PushMetaTable(IMAGEREADER_METATABLE);
	LUA->SetMetaTable(-2);

	return 1;
}

LUA_FUNCTION(IMAGEREADER_GarbageCollect) {
	LUA->CheckType(1, IMAGEREADER_METATABLE);

	const auto image_reader = LUA->GetUserType<ImageReader>(1, IMAGEREADER_METATABLE);
	if (!image_reader) return 0;

	stbi_image_free(image_reader->data);
	delete image_reader;

	return 0;
}

LUA_FUNCTION(IMAGEREADER_Get) {
	LUA->CheckType(1, IMAGEREADER_METATABLE);
	LUA->CheckType(2, GarrysMod::Lua::Type::Number); // x (0 : 1)
	LUA->CheckType(3, GarrysMod::Lua::Type::Number); // y (0 : 1)

	const auto image_reader = LUA->GetUserType<ImageReader>(1, IMAGEREADER_METATABLE);
	if (!image_reader) return 0;

	const int width = image_reader->width;
	const int height = image_reader->height;
	const int stride = image_reader->stride;
	const uint16_t* data = image_reader->data;

	auto get_data = [width, height, stride, data](int x, int y, int s) {
		x = clamp(x, 0, width - 1);
		y = clamp(y, 0, height - 1);
		return data[(y * width + x) * stride + s];
	};

	double x = LUA->GetNumber(2) * width;
	double y = (1.0 - LUA->GetNumber(3)) * height; // make 0,0 bottom left instead of top left

	if (LUA->GetBool(4)) {
		// Point filtering
		for (int i = 0; i < stride; i++) {
			LUA->PushNumber(get_data(x, y, i));
		}
	}
	else {
		// Bilinear filtering
		double x_fract = x - (int)x;
		double y_fract = y - (int)y;
		int x_offset = x_fract >= 0.5 ? 1 : -1;
		int y_offset = y_fract >= 0.5 ? 1 : -1;
		double x_dist = std::abs(x_fract - 0.5);
		double y_dist = std::abs(y_fract - 0.5);
		for (int i = 0; i < stride; i++) {
			double c00 = get_data(x,            y           , i);
			double c10 = get_data(x + x_offset, y           , i);
			double c01 = get_data(x           , y + y_offset, i);
			double c11 = get_data(x + x_offset, y + y_offset, i);

			LUA->PushNumber(
				(c00 * (1.0 - x_dist) + c10 * x_dist) * (1.0 - y_dist) +
				(c01 * (1.0 - x_dist) + c11 * x_dist) * (      y_dist)
			);
		}
	}

	return stride;
}

#define ADD_FUNCTION(LUA, func, tbl) LUA->PushCFunction(func); LUA->SetField(-2, tbl)
GMOD_MODULE_OPEN() {
	IMAGEREADER_METATABLE = LUA->CreateMetaTable("ImageReader");
		ADD_FUNCTION(LUA, IMAGEREADER_GarbageCollect, "__gc");

		LUA->CreateTable();
			ADD_FUNCTION(LUA, IMAGEREADER_Get, "Get");
		LUA->SetField(-2, "__index");
	LUA->Pop();

	LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
		ADD_FUNCTION(LUA, IMAGEREADER_ImageReader, "ImageReader");
	LUA->Pop();

	return 0;
}

GMOD_MODULE_CLOSE() {
	return 0;
}