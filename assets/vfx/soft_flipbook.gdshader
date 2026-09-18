shader_type spatial;
render_mode blend_mix,depth_draw_never,cull_disabled,unshaded;
uniform sampler2D atlas:source_color,filter_linear_mipmap,repeat_disable;
uniform sampler2D flow:filter_linear_mipmap,repeat_disable;
uniform sampler2D depth_texture:hint_depth_texture,repeat_disable,filter_nearest;
uniform float progress=0.0;
uniform float opacity=1.0;
uniform float soft_distance=.025;
uniform vec3 tint=vec3(1.0);
uniform bool smoke_only=false;
void vertex(){
 float sx=length(MODEL_MATRIX[0].xyz);float sy=length(MODEL_MATRIX[1].xyz);
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(INV_VIEW_MATRIX[0].xyz*sx,0.0),vec4(INV_VIEW_MATRIX[1].xyz*sy,0.0),vec4(INV_VIEW_MATRIX[2].xyz,0.0),MODEL_MATRIX[3]);
}
void fragment(){
 float frame=clamp(progress,0.0,.999)*24.0;float a=floor(frame);float b=min(a+1.0,24.0);float mixf=fract(frame);
 vec2 uva=(UV+vec2(mod(a,5.0),floor(a/5.0)))/5.0;
 vec2 uvb=(UV+vec2(mod(b,5.0),floor(b/5.0)))/5.0;
 vec2 fv=(texture(flow,uva).rg-.5)*.006;
 vec4 tex=mix(texture(atlas,uva-fv*mixf),texture(atlas,uvb+fv*(1.0-mixf)),mixf);
 float depth=texture(depth_texture,SCREEN_UV).r;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 vec3 ndc=vec3(SCREEN_UV,depth)*2.0-1.0;
 #else
 vec3 ndc=vec3(SCREEN_UV*2.0-1.0,depth);
 #endif
 vec4 world=INV_PROJECTION_MATRIX*vec4(ndc,1.0);float sd=-world.z/world.w;
 float fade=clamp((sd+VERTEX.z)/soft_distance,0.0,1.0);
 float lum=dot(tex.rgb,vec3(.299,.587,.114));
 vec3 c=smoke_only?vec3(lum*.4+.13):tex.rgb;
 ALBEDO=c*tint;ALPHA=tex.a*opacity*fade*(1.0-smoothstep(.8,1.0,progress));
}
