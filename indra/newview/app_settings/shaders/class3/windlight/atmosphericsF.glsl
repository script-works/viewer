/** 
 * @file atmosphericsF.glsl
 *
 * $LicenseInfo:firstyear=2007&license=viewerlgpl$
 * Second Life Viewer Source Code
 * Copyright (C) 2007, Linden Research, Inc.
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation;
 * version 2.1 of the License only.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 * 
 * Linden Research, Inc., 945 Battery Street, San Francisco, CA  94111  USA
 * $/LicenseInfo$
 */

vec3 getAdditiveColor();
vec3 getAtmosAttenuation();

uniform vec4 gamma;
uniform vec4 lightnorm;
uniform vec4 sunlight_color;
uniform vec4 ambient;
uniform vec4 blue_horizon;
uniform vec4 blue_density;
uniform float haze_horizon;
uniform float haze_density;
uniform float cloud_shadow;
uniform float density_multiplier;
uniform float distance_multiplier;
uniform float max_y;
uniform vec4 glow;
uniform float scene_light_strength;
uniform mat3 ssao_effect_mat;

vec3 scaleFragSoftClip(vec3 light)
{
	//soft clip effect:
	light = 1. - clamp(light, vec3(0.), vec3(1.));
	light = 1. - pow(light, gamma.xxx);
	return light;
}

vec3 atmosFragLighting(vec3 light, vec3 additive, vec3 atten)
{
	light *= atten.r;
	light += additive;
	return (2.0 * light);
}

vec3 atmosLighting(vec3 light)
{
    return atmosFragLighting(light, getAdditiveColor(), getAtmosAttenuation());
}

void calcFragAtmospherics(vec3 inPositionEye, float ambFactor, out vec3 sunlit, out vec3 amblit, out vec3 additive, out vec3 atten) {

	vec3 P = inPositionEye;
	
	vec3 tmpLightnorm = lightnorm.xyz;

	vec3 Pn = normalize(P);
	float Plen = length(P);

	vec4 temp1 = vec4(0);
	vec3 temp2 = vec3(0);
	vec4 blue_weight;
	vec4 haze_weight;
	vec4 sunlight = sunlight_color;
	vec4 light_atten;

	//sunlight attenuation effect (hue and brightness) due to atmosphere
	//this is used later for sunlight modulation at various altitudes
	light_atten = (blue_density + vec4(haze_density * 0.25)) * (density_multiplier * max_y);
		//I had thought blue_density and haze_density should have equal weighting,
		//but attenuation due to haze_density tends to seem too strong

	temp1 = blue_density + vec4(haze_density);
	blue_weight = blue_density / temp1;
	haze_weight = vec4(haze_density) / temp1;

	//(TERRAIN) compute sunlight from lightnorm only (for short rays like terrain)
	temp2.y = max(0.0, tmpLightnorm.y);
	temp2.y = 1. / temp2.y;
	sunlight *= exp( - light_atten * temp2.y);

	// main atmospheric scattering line integral
	temp2.z = Plen * density_multiplier;

	// Transparency (-> temp1)
	// ATI Bugfix -- can't store temp1*temp2.z*distance_multiplier in a variable because the ati
	// compiler gets confused.
	temp1 = exp(-temp1 * temp2.z * distance_multiplier);

	//final atmosphere attenuation factor
	atten = temp1.rgb;
	
	//compute haze glow
	//(can use temp2.x as temp because we haven't used it yet)
	temp2.x = dot(Pn, tmpLightnorm.xyz);
	temp2.x = 1. - temp2.x;
		//temp2.x is 0 at the sun and increases away from sun
	temp2.x = max(temp2.x, .03);	//was glow.y
		//set a minimum "angle" (smaller glow.y allows tighter, brighter hotspot)
	temp2.x *= glow.x;
		//higher glow.x gives dimmer glow (because next step is 1 / "angle")
	temp2.x = pow(temp2.x, glow.z);
		//glow.z should be negative, so we're doing a sort of (1 / "angle") function

	//add "minimum anti-solar illumination"
	temp2.x += .25;
	
	//increase ambient when there are more clouds
	vec4 tmpAmbient = ambient + (vec4(1.) - ambient) * cloud_shadow * 0.5;
	
	/*  decrease value and saturation (that in HSV, not HSL) for occluded areas
	 * // for HSV color/geometry used here, see http://gimp-savvy.com/BOOK/index.html?node52.html
	 * // The following line of code performs the equivalent of:
	 * float ambAlpha = tmpAmbient.a;
	 * float ambValue = dot(vec3(tmpAmbient), vec3(0.577)); // projection onto <1/rt(3), 1/rt(3), 1/rt(3)>, the neutral white-black axis
	 * vec3 ambHueSat = vec3(tmpAmbient) - vec3(ambValue);
	 * tmpAmbient = vec4(RenderSSAOEffect.valueFactor * vec3(ambValue) + RenderSSAOEffect.saturationFactor *(1.0 - ambFactor) * ambHueSat, ambAlpha);
	 */
	tmpAmbient = vec4(mix(ssao_effect_mat * tmpAmbient.rgb, tmpAmbient.rgb, ambFactor), tmpAmbient.a);

	//haze color
        additive =
		vec3(blue_horizon * blue_weight * (sunlight*(1.-cloud_shadow) + tmpAmbient)
     	          + (haze_horizon * haze_weight) * (sunlight*(1.-cloud_shadow) * temp2.x
		  + tmpAmbient));

	//brightness of surface both sunlight and ambient
	sunlit = vec3(sunlight * .5);
	amblit = vec3(tmpAmbient * .25);
	additive *= vec3(1.0 - temp1);
}
