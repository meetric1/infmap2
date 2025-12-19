-- experimental .png sampler for client (wip, not fully implemented)
--[[
local INFMAP_SAMPLER_FUNCS = {
	["Dump"] = function(self, pos, size)
		-- "dumping" the entire rendertarget for every sample is really inefficient
		-- So we render the material into a smaller rendertarget and then dump that
		-- pos and size are both 0:1 inclusive
		local w, h = self.width, self.height
		local inv_res = 1 / self.render_target:GetWidth()
		local function vertex(x, y, u, v)
			mesh.Position(x, y, 0)
			mesh.TexCoord(0, u, v)
			mesh.AdvanceVertex()
		end

		cam.Start2D()
			render.PushRenderTarget(self.render_target)
				render.SetMaterial(self.material)
				local u0 = (pos[1] * w - 1)
				local u1 = u0 + inv_res
				mesh.Begin(MATERIAL_QUADS, 1)
					vertex(0,     0, -1, -1)
					vertex(res,   0, 0, 0)
					vertex(res, res, 0, 0)
					vertex(0,   res, 0, 0)
				mesh.End()
				--render.DrawScreenQuadEx(
				--	(  - pos[1]) * w - 1, 
				--	(1 - pos[2]) * h - 1, 
				--	size * w + 1, 
				--	size * h + 1
				--)
				render.CapturePixels()
			render.PopRenderTarget()
		cam.End2D()
	end,
	["Get"] = function(self, x, y, point)
		if point then
			-- point filtering
			return render.ReadPixel(x + 1, y + 1)
		else
			-- bilinear filtering

		end
	end
}

local INFMAP_SAMPLER = {
	["__index"] = INFMAP_SAMPLER_FUNCS
}

function INFMAP.Sampler(path, res)
	res = res + 2 -- extra res at outer edge, for interpolation

	local material = Material(path .. ".png")
	local render_target = GetRenderTargetEx(
		"infmap_sampler_" .. res, 
		res + 2, 
		res + 2, 
		RT_SIZE_NO_CHANGE,
		MATERIAL_RT_DEPTH_NONE, 
		1 + 4 + 8 + 256, -- pixel filtering, clampU, clampV, nomips
		0,               -- no createrendertargetflags
		IMAGE_FORMAT_RGB888
	)

	return setmetatable({
		["material"] = material,
		["width"] = material:Width(),
		["height"] = material:Height(),
		["render_target"] = render_target
	}, INFMAP_SAMPLER)
end]]