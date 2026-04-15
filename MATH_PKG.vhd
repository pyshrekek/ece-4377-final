-- ============================================================
-- MATH_PKG.VHD
-- Vector math for the 3D graphics pipeline
-- ECE 4377 Final Project
--
-- Depends on: types.VHD  (fp, vec3, vec4, mat3, FP_WIDTH, FP_FRAC, FP_ZERO)
--
-- What's here and why:
--
--   fp_mul   (a, b : fp)      -> fp      internal helper, Q8.8 multiply
--   fp_add   (a, b : fp)      -> fp      internal helper, saturating add
--   fp_sub   (a, b : fp)      -> fp      internal helper, saturating sub
--
--   dot3     (a, b : vec3)    -> fp      lighting: N·L, back-face cull
--   cross3   (a, b : vec3)    -> vec3    face normal from two edges
--   magnitude3 (a  : vec3)    -> fp      used only inside normalize3
--   normalize3 (a  : vec3)    -> vec3    unit normal for lighting
--
--   mat3_mul_vec3 (M : mat3; v : vec3) -> vec3
--       Transform a normal by the upper-left 3x3 of a mat4.
--       Used in lighting to keep normals correct after rotation.
--       (Translation must NOT be applied to normals, which is why
--        we use mat3 here rather than the full MATRIX_MULT entity.)
--
-- What's intentionally NOT here:
--   vec2 / mat2 ops  -- no texture mapping in scope
--   mat4 ops         -- handled by MATRIX_MULT.vhd (pipelined entity)
--   mat3 inverse     -- not needed; we only rotate unit normals
-- ============================================================

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.types.ALL;

PACKAGE math_pkg IS

    FUNCTION dot3          (a, b : vec3)         RETURN fp;
    FUNCTION cross3        (a, b : vec3)         RETURN vec3;
    FUNCTION magnitude3    (a    : vec3)         RETURN fp;
    FUNCTION normalize3    (a    : vec3)         RETURN vec3;
    FUNCTION mat3_mul_vec3 (M : mat3; v : vec3)  RETURN vec3;

END PACKAGE math_pkg;


PACKAGE BODY math_pkg IS

    -- ----------------------------------------------------------
    -- fp_mul: Q8.8 * Q8.8 -> Q8.8, with saturation
    -- 32-bit intermediate product shifted right by FP_FRAC (8).
    -- ----------------------------------------------------------
    FUNCTION fp_mul (a, b : fp) RETURN fp IS
        VARIABLE prod    : signed(2 * FP_WIDTH - 1 DOWNTO 0);
        CONSTANT SAT_MAX : signed(2 * FP_WIDTH - 1 DOWNTO 0) :=
            to_signed((2**(FP_WIDTH-1) - 1) * (2**FP_FRAC), 2*FP_WIDTH);
        CONSTANT SAT_MIN : signed(2 * FP_WIDTH - 1 DOWNTO 0) :=
            to_signed(-(2**(FP_WIDTH-1)) * (2**FP_FRAC), 2*FP_WIDTH);
    BEGIN
        prod := a * b;
        IF    prod > SAT_MAX THEN RETURN to_signed( 2**(FP_WIDTH-1)-1, FP_WIDTH);
        ELSIF prod < SAT_MIN THEN RETURN to_signed(-(2**(FP_WIDTH-1)), FP_WIDTH);
        ELSE                      RETURN prod(FP_WIDTH + FP_FRAC - 1 DOWNTO FP_FRAC);
        END IF;
    END FUNCTION fp_mul;

    -- ----------------------------------------------------------
    -- fp_add / fp_sub: saturating 16-bit add/sub
    -- ----------------------------------------------------------
    FUNCTION fp_add (a, b : fp) RETURN fp IS
        VARIABLE s : signed(FP_WIDTH DOWNTO 0);
    BEGIN
        s := resize(a, FP_WIDTH+1) + resize(b, FP_WIDTH+1);
        IF    s > to_signed( 2**(FP_WIDTH-1)-1, FP_WIDTH+1) THEN RETURN to_signed( 2**(FP_WIDTH-1)-1, FP_WIDTH);
        ELSIF s < to_signed(-(2**(FP_WIDTH-1)), FP_WIDTH+1) THEN RETURN to_signed(-(2**(FP_WIDTH-1)), FP_WIDTH);
        ELSE RETURN s(FP_WIDTH-1 DOWNTO 0);
        END IF;
    END FUNCTION fp_add;

    FUNCTION fp_sub (a, b : fp) RETURN fp IS
        VARIABLE s : signed(FP_WIDTH DOWNTO 0);
    BEGIN
        s := resize(a, FP_WIDTH+1) - resize(b, FP_WIDTH+1);
        IF    s > to_signed( 2**(FP_WIDTH-1)-1, FP_WIDTH+1) THEN RETURN to_signed( 2**(FP_WIDTH-1)-1, FP_WIDTH);
        ELSIF s < to_signed(-(2**(FP_WIDTH-1)), FP_WIDTH+1) THEN RETURN to_signed(-(2**(FP_WIDTH-1)), FP_WIDTH);
        ELSE RETURN s(FP_WIDTH-1 DOWNTO 0);
        END IF;
    END FUNCTION fp_sub;

    -- ----------------------------------------------------------
    -- isqrt32: integer square root, floor(sqrt(n))
    -- Restoring algorithm — no divides, no reserved words.
    -- ----------------------------------------------------------
    FUNCTION isqrt32 (n : unsigned(31 DOWNTO 0)) RETURN unsigned IS
        VARIABLE val  : unsigned(31 DOWNTO 0);
        VARIABLE root : unsigned(15 DOWNTO 0);
        VARIABLE bit  : unsigned(31 DOWNTO 0);
        VARIABLE tmp  : unsigned(31 DOWNTO 0);
    BEGIN
        val  := n;
        root := (OTHERS => '0');
        bit  := to_unsigned(1, 32) SLL 30;
        WHILE bit > val LOOP
            bit := bit SRL 2;
        END LOOP;
        WHILE bit /= to_unsigned(0, 32) LOOP
            tmp := resize(root, 32) + bit;
            IF val >= tmp THEN
                val  := val - tmp;
                root := resize(('0' & root(15 DOWNTO 1)) OR
                                resize(bit(15 DOWNTO 0), 16), 16);
            ELSE
                root := '0' & root(15 DOWNTO 1);
            END IF;
            bit := bit SRL 2;
        END LOOP;
        RETURN root;
    END FUNCTION isqrt32;

    -- ----------------------------------------------------------
    -- Reciprocal LUT: RECIP_LUT(i) = round(65536 / i)
    -- Index = integer part of magnitude (mag_q8 >> FP_FRAC).
    -- Used in normalize3 as: result = (component * RECIP_LUT(i)) >> 16
    -- This gives component_real / magnitude_real in Q8.8.
    -- ----------------------------------------------------------
    TYPE recip_table_t IS ARRAY (0 TO 255) OF INTEGER;
    CONSTANT RECIP_LUT : recip_table_t := (
            0, 32767, 32767, 21845, 16384, 13107, 10923,  9362,
         8192,  7282,  6554,  5958,  5461,  5041,  4681,  4369,
         4096,  3855,  3641,  3449,  3277,  3121,  2979,  2849,
         2731,  2621,  2521,  2427,  2341,  2260,  2185,  2114,
         2048,  1986,  1928,  1872,  1820,  1771,  1725,  1680,
         1638,  1598,  1560,  1524,  1489,  1456,  1425,  1394,
         1365,  1337,  1311,  1285,  1260,  1237,  1214,  1192,
         1170,  1150,  1130,  1111,  1092,  1074,  1057,  1040,
         1024,  1008,   993,   978,   964,   950,   936,   923,
          910,   898,   886,   874,   862,   851,   840,   830,
          819,   809,   799,   790,   780,   771,   762,   753,
          745,   736,   728,   720,   712,   705,   697,   690,
          683,   676,   669,   662,   655,   649,   643,   636,
          630,   624,   618,   612,   607,   601,   596,   590,
          585,   580,   575,   570,   565,   560,   555,   551,
          546,   542,   537,   533,   529,   524,   520,   516,
          512,   508,   504,   500,   496,   493,   489,   485,
          482,   478,   475,   471,   468,   465,   462,   458,
          455,   452,   449,   446,   443,   440,   437,   434,
          431,   428,   426,   423,   420,   417,   415,   412,
          410,   407,   405,   402,   400,   397,   395,   392,
          390,   388,   386,   383,   381,   379,   377,   374,
          372,   370,   368,   366,   364,   362,   360,   358,
          356,   354,   352,   350,   349,   347,   345,   343,
          341,   340,   338,   336,   334,   333,   331,   329,
          328,   326,   324,   323,   321,   320,   318,   317,
          315,   314,   312,   311,   309,   308,   306,   305,
          303,   302,   301,   299,   298,   297,   295,   294,
          293,   291,   290,   289,   287,   286,   285,   284,
          282,   281,   280,   279,   278,   277,   275,   274,
          273,   272,   271,   270,   269,   267,   266,   265,
          264,   263,   262,   261,   260,   259,   258,   257
    );

    -- ==========================================================
    -- dot3: a.x*b.x + a.y*b.y + a.z*b.z
    -- Primary use: N·L for diffuse lighting, sign test for back-face culling
    -- ==========================================================
    FUNCTION dot3 (a, b : vec3) RETURN fp IS
    BEGIN
        RETURN fp_add(fp_add(fp_mul(a.x, b.x),
                             fp_mul(a.y, b.y)),
                             fp_mul(a.z, b.z));
    END FUNCTION dot3;

    -- ==========================================================
    -- cross3: a x b  (right-hand rule)
    -- Primary use: compute face normal from two triangle edge vectors
    --   edge1 = v1 - v0,  edge2 = v2 - v0
    --   normal = cross3(edge1, edge2)
    -- ==========================================================
    FUNCTION cross3 (a, b : vec3) RETURN vec3 IS
        VARIABLE r : vec3;
    BEGIN
        r.x := fp_sub(fp_mul(a.y, b.z), fp_mul(a.z, b.y));
        r.y := fp_sub(fp_mul(a.z, b.x), fp_mul(a.x, b.z));
        r.z := fp_sub(fp_mul(a.x, b.y), fp_mul(a.y, b.x));
        RETURN r;
    END FUNCTION cross3;

    -- ==========================================================
    -- magnitude3: |a| = sqrt(a.x^2 + a.y^2 + a.z^2)
    -- Each fp_mul produces Q8.8; sum three, then isqrt32.
    -- isqrt output is Q4.4 (sqrt halves frac bits), so shift
    -- left by FP_FRAC/2 = 4 to restore Q8.8.
    -- ==========================================================
    FUNCTION magnitude3 (a : vec3) RETURN fp IS
        VARIABLE sq_x, sq_y, sq_z : fp;
        VARIABLE sum_sq  : signed(FP_WIDTH + 1 DOWNTO 0);
        VARIABLE sum_u   : unsigned(31 DOWNTO 0);
        VARIABLE root    : unsigned(15 DOWNTO 0);
        VARIABLE res_int : INTEGER;
    BEGIN
        sq_x := fp_mul(a.x, a.x);
        sq_y := fp_mul(a.y, a.y);
        sq_z := fp_mul(a.z, a.z);
        sum_sq := resize(sq_x, FP_WIDTH+2) +
                  resize(sq_y, FP_WIDTH+2) +
                  resize(sq_z, FP_WIDTH+2);
        IF sum_sq < 0 THEN
            sum_u := (OTHERS => '0');
        ELSE
            sum_u := unsigned(resize(sum_sq, 32));
        END IF;
        root    := isqrt32(sum_u);
        res_int := to_integer(root) * 16;  -- restore Q8.8 from Q4.4
        IF res_int > 2**(FP_WIDTH-1)-1 THEN
            RETURN to_signed(2**(FP_WIDTH-1)-1, FP_WIDTH);
        ELSE
            RETURN to_signed(res_int, FP_WIDTH);
        END IF;
    END FUNCTION magnitude3;

    -- ==========================================================
    -- normalize3: return unit-length vector in direction of a
    -- Uses RECIP_LUT(mag_integer_part) to avoid true division.
    --   result_component = (component_q8 * RECIP_LUT(i)) >> 16
    -- This is equivalent to component_real / magnitude_real in Q8.8.
    -- Returns zero vector if magnitude is zero.
    -- ==========================================================
    FUNCTION normalize3 (a : vec3) RETURN vec3 IS
        VARIABLE mag      : fp;
        VARIABLE mag_int  : INTEGER;
        VARIABLE lut_idx  : INTEGER RANGE 0 TO 255;
        VARIABLE lut_val  : INTEGER;
        VARIABLE result   : vec3;
        -- Use 32-bit intermediates for the >>16 multiply
        VARIABLE px, py, pz : signed(31 DOWNTO 0);
    BEGIN
        mag     := magnitude3(a);
        mag_int := to_integer(mag);

        IF mag_int <= 0 THEN
            result.x := FP_ZERO;
            result.y := FP_ZERO;
            result.z := FP_ZERO;
            RETURN result;
        END IF;

        -- Integer part of Q8.8 magnitude
        lut_idx := mag_int / (2**FP_FRAC);
        IF lut_idx < 1   THEN lut_idx := 1;   END IF;
        IF lut_idx > 255 THEN lut_idx := 255; END IF;

        lut_val := RECIP_LUT(lut_idx);

        -- (component_q8 * lut_val) >> 16  gives Q8.8 result
        px := to_signed(to_integer(a.x) * lut_val, 32);
        py := to_signed(to_integer(a.y) * lut_val, 32);
        pz := to_signed(to_integer(a.z) * lut_val, 32);

        result.x := px(2*FP_WIDTH - 1 DOWNTO FP_WIDTH);
        result.y := py(2*FP_WIDTH - 1 DOWNTO FP_WIDTH);
        result.z := pz(2*FP_WIDTH - 1 DOWNTO FP_WIDTH);
        RETURN result;
    END FUNCTION normalize3;

    -- ==========================================================
    -- mat3_mul_vec3: M * v  (3x3 matrix times vec3)
    -- Used to rotate normals without applying translation.
    -- Caller should extract the upper-left 3x3 of their mat4:
    --   M3(r,c) := M4(r,c) for r,c in 0..2
    -- ==========================================================
    FUNCTION mat3_mul_vec3 (M : mat3; v : vec3) RETURN vec3 IS
        VARIABLE r   : vec3;
        VARIABLE v_a : vec3;
    BEGIN
        v_a := v;
        r.x := fp_add(fp_add(fp_mul(M(0,0), v_a.x),
                             fp_mul(M(0,1), v_a.y)),
                             fp_mul(M(0,2), v_a.z));
        r.y := fp_add(fp_add(fp_mul(M(1,0), v_a.x),
                             fp_mul(M(1,1), v_a.y)),
                             fp_mul(M(1,2), v_a.z));
        r.z := fp_add(fp_add(fp_mul(M(2,0), v_a.x),
                             fp_mul(M(2,1), v_a.y)),
                             fp_mul(M(2,2), v_a.z));
        RETURN r;
    END FUNCTION mat3_mul_vec3;

END PACKAGE BODY math_pkg;
