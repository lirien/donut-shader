precision mediump float;
uniform vec3      iResolution;           // viewport resolution (in pixels)
uniform float     iGlobalTime;           // shader playback time (in seconds)
uniform float     iTimeDelta;            // render time (in seconds)
uniform int       iFrame;                // shader playback frame
uniform float     iChannelTime[4];       // channel playback time (in seconds)
uniform vec3      iChannelResolution[4]; // channel resolution (in pixels)
uniform vec4      iMouse;                // mouse pixel coords. xy: current (if MLB down), zw: click
//uniform samplerXX iChannel0..3;        // input channel. XX = 2D/Cube
uniform vec4      iDate;                 // (year, month, day, time in seconds)
uniform float     iSampleRate;           // sound sample rate (i.e., 44100)

#define PI 3.14159265358979323846

//------------------------------------------------------------------------
// Camera
//
// Move the camera. In this case it's using time and the mouse position
// to orbitate the camera around the origin of the world (0,0,0), where
// the yellow sphere is.
//------------------------------------------------------------------------
void doCamera(out vec3 camPos, out vec3 camTar, in float time, in float mouseX) {
  float an = 0.3 * iGlobalTime + 10.0 * mouseX;
  camPos = vec3(3.5 * sin(an), 1.0, 3.5 * cos(an));
  camTar = vec3(0.0, 0.0, 0.0);
}

//------------------------------------------------------------------------
// Background
//
// The background color. In this case it's just a black color.
//------------------------------------------------------------------------
vec3 doBackground(void) {
  return vec3(0.0, 0.0, 0.0);
}

//------------------------------------------------------------------------
// Modelling
//
// Defines the shapes (a sphere in this case) through a distance field, in
// this case it's a torus.
//------------------------------------------------------------------------
float doModel(vec3 p) {

  //translation matrix
  vec4 tm_column0 = vec4(1.0, 0.0, 0.0, 0.0);
  vec4 tm_column1 = vec4(0.0, 1.0, 0.0, 0.0);
  vec4 tm_column2 = vec4(0.0, 0.0, 1.0, 0.0);
  vec4 tm_column3 = vec4(0.5, 0.5, 0.0, 1.0);

  mat4 transMatrix = mat4(tm_column0, tm_column1, tm_column2, tm_column3);
  vec4 point4 = vec4(p.x, p.y, p.z, 1.0);
  point4 = transMatrix * point4;

  //rotation matrix
  vec3 rm_column0 = vec3(cos(PI / 4.0), sin(PI / 4.0), 0.0);
  vec3 rm_column1 = vec3(-sin(PI / 4.0), cos(PI / 4.0), 0.0);
  vec3 rm_column2 = vec3(0.0, 0.0, 1.0);

  mat3 rotationMatrix = mat3(rm_column0, rm_column1, rm_column2);
  vec3 point3 = point4.xyz;
  point3 = rotationMatrix * point3;

  vec2 t = vec2(1.0, 0.5);
  vec2 q = vec2(length(point3.xz) - t.x, point3.y);
  return length(q) - t.y;
}

//------------------------------------------------------------------------
// Material
//
// Defines the material (colors, shading, pattern, texturing) of the model
// at every point based on its position and normal. In this case, it simply
// returns a constant color.
//------------------------------------------------------------------------
vec3 doMaterial(in vec3 pos, in vec3 nor) {
  return vec3(0.157, 0.078, 0.027);
}

//------------------------------------------------------------------------
// Lighting
//------------------------------------------------------------------------
float calcSoftshadow(in vec3 ro, in vec3 rd);

vec3 doLighting(in vec3 pos, in vec3 nor, in vec3 rd, in float dis, in vec3 mal) {
  vec3 lin = vec3(0.0);

  // key light
  //-----------------------------
  vec3  lig = normalize(vec3(1.0, 0.7, 0.9));
  float dif = max(dot(nor, lig), 0.0);
  float sha = 0.0; if(dif > 0.01) sha = calcSoftshadow(pos + 0.01 * nor, lig);
  lin += dif * vec3(4.00, 4.00, 4.00) * sha;

  // ambient light
  //-----------------------------
  lin += vec3(0.50, 0.50, 0.50);

  // surface-light interacion
  //-----------------------------
  vec3 col = mal * lin;

  // fog
  //-----------------------------
  col *= exp(-0.01 * dis * dis);
  return col;
}

float calcIntersection(in vec3 ro, in vec3 rd) {
  const float maxd = 20.0;          // max trace distance
  const float precis = 0.001;       // precision of the intersection
  float h = precis * 2.0;
  float t = 0.0;
  float res = -1.0;

  // max number of raymarching iterations is 90
  for(int i = 0; i < 90; i++) {
    if(h < precis || t > maxd)
      break;
    h = doModel(ro + rd * t);
    t += h;
  }

  if(t < maxd) res = t;
  return res;
}

vec3 calcNormal(in vec3 pos) {
  const float eps = 0.002;          // precision of the normal computation

  const vec3 v1 = vec3(1.0, -1.0, -1.0);
  const vec3 v2 = vec3(-1.0, -1.0, 1.0);
  const vec3 v3 = vec3(-1.0, 1.0, -1.0);
  const vec3 v4 = vec3(1.0, 1.0, 1.0);

  return normalize(v1 * doModel(pos + v1 * eps) +
                   v2 * doModel(pos + v2 * eps) +
                   v3 * doModel(pos + v3 * eps) +
                   v4 * doModel(pos + v4 * eps));
}

float calcSoftshadow(in vec3 ro, in vec3 rd) {
  float res = 1.0;
  float t = 0.0005;               // selfintersection avoidance distance
  float h = 1.0;

  // 40 is the max numnber of raymarching steps
  for(int i = 0; i < 40; i++) {
    h = doModel(ro + rd * t);
    res = min(res, 64.0 * h / t); // 64 is the hardness of the shadows
    t += clamp(h, 0.02, 2.0);     // limit the max and min stepping distances
  }
  return clamp(res, 0.0, 1.0);
}

mat3 calcLookAtMatrix(in vec3 ro, in vec3 ta, in float roll) {
  vec3 ww = normalize(ta - ro);
  vec3 uu = normalize(cross(ww, vec3(sin(roll), cos(roll), 0.0)));
  vec3 vv = normalize(cross(uu, ww));
  return mat3(uu, vv, ww);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 p = (-iResolution.xy + 2.0 * fragCoord.xy) / iResolution.y;
  vec2 m = iMouse.xy / iResolution.xy;

  //-----------------------------------------------------
  // camera
  //-----------------------------------------------------

  // camera movement
  vec3 ro, ta;
  doCamera(ro, ta, iGlobalTime, m.x);

  // camera matrix
  mat3 camMat = calcLookAtMatrix(ro, ta, 0.0);  // 0.0 is the camera roll

  // create view ray
  vec3 rd = normalize(camMat * vec3(p.xy, 2.0)); // 2.0 is the lens length

  //-----------------------------------------------------
  // render
  //-----------------------------------------------------

  vec3 col = doBackground();

  // raymarch
  float t = calcIntersection(ro, rd);
  if(t > -0.5) {
    // geometry
    vec3 pos = ro + t * rd;
    vec3 nor = calcNormal(pos);

    // materials
    vec3 mal = doMaterial(pos, nor);
    col = doLighting(pos, nor, rd, t, mal);
  }

  //-----------------------------------------------------
  // postprocessing
  //-----------------------------------------------------
  // gamma
  col = pow(clamp(col, 0.0, 1.0), vec3(0.4545));
  fragColor = vec4(col, 1.0);
}
