--!strict

-- Back-compat shim; cape + glide logic lives in CapeVfx.

local CapeVfx = require(script.Parent.CapeVfx)

local GlideVfx = {}

GlideVfx.setEquippedTrailColor = CapeVfx.setEquippedTrailColor
GlideVfx.setGlideTrailColor = CapeVfx.setGlideTrailColor
GlideVfx.isGlidePhase = CapeVfx.isGlidePhase
GlideVfx.setGlideActive = CapeVfx.setGlideActive
GlideVfx.cleanupCharacter = CapeVfx.cleanupCharacter

return GlideVfx
