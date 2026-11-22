import math
import json
import random
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "assets" / "models"
PREVIEW_DIR = Path("/home/ubuntu/specs/shots/v4/models")
PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
MODEL_DIR.mkdir(parents=True, exist_ok=True)

MATERIALS = {
    "Paint_Orange": ((0.86, 0.22, 0.055, 1.0), 0.24, 0.38),
    "Paint_Dark": ((0.105, 0.135, 0.13, 1.0), 0.42, 0.42),
    "Steel": ((0.34, 0.39, 0.37, 1.0), 0.68, 0.36),
    "Concrete": ((0.35, 0.37, 0.33, 1.0), 0.02, 0.92),
    "Glass": ((0.11, 0.35, 0.39, 1.0), 0.3, 0.18),
    "Rubber": ((0.035, 0.045, 0.043, 1.0), 0.0, 0.86),
    "Hazard": ((0.95, 0.57, 0.055, 1.0), 0.22, 0.48),
    "Emissive_Furnace": ((1.0, 0.22, 0.025, 1.0), 0.0, 0.28),
    "Emissive_Status": ((0.18, 0.9, 0.33, 1.0), 0.05, 0.2),
    "Foliage": ((0.18, 0.34, 0.15, 1.0), 0.0, 0.9),
    "GrassBlade": ((0.18, 0.34, 0.15, 1.0), 0.0, 0.9),
    "Bark": ((0.22, 0.13, 0.08, 1.0), 0.0, 0.95),
    "Ore_Iron": ((0.47, 0.19, 0.11, 1.0), 0.1, 0.88),
    "Ore_Copper": ((0.21, 0.43, 0.35, 1.0), 0.16, 0.72),
    "Ore_Limestone": ((0.72, 0.68, 0.52, 1.0), 0.0, 0.91),
}

MATERIAL_CACHE = {}
TRI_COUNTS = {}


def material(name):
    if name in MATERIAL_CACHE:
        return MATERIAL_CACHE[name]
    color, metallic, roughness = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if name == "Emissive_Furnace":
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = 4.0
    elif name == "Emissive_Status":
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = 2.0
    elif name == "GrassBlade":
        vertex_color = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        vertex_color.layer_name = "Color"
        mat.node_tree.links.new(vertex_color.outputs["Color"], shader.inputs["Base Color"])
    if name == "Hazard":
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        tex = nodes.new("ShaderNodeTexWave")
        tex.wave_type = "BANDS"
        tex.bands_direction = "X"
        tex.inputs["Scale"].default_value = 8.0
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.42
        ramp.color_ramp.elements[0].color = (0.035, 0.045, 0.04, 1.0)
        ramp.color_ramp.elements[1].position = 0.52
        ramp.color_ramp.elements[1].color = color
        links.new(tex.outputs["Color"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    MATERIAL_CACHE[name] = mat
    return mat


def empty(name, parent=None, location=(0.0, 0.0, 0.0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.empty_display_type = "PLAIN_AXES"
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = location
    return obj


def attach(obj, parent, location, rotation=(0.0, 0.0, 0.0)):
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def finish_mesh(obj, mat_name, bevel=0.025, segments=2, smooth=False):
    obj.data.materials.append(material(mat_name))
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    if bevel > 0.0:
        bevel_mod = obj.modifiers.new("Machined_Edge_Bevel", "BEVEL")
        bevel_mod.width = bevel
        bevel_mod.segments = 1
        bevel_mod.limit_method = "ANGLE"
        bevel_mod.angle_limit = math.radians(28.0)
        bevel_mod.harden_normals = True
    normal_mod = obj.modifiers.new("Weighted_Highlight_Normals", "WEIGHTED_NORMAL")
    normal_mod.keep_sharp = True
    normal_mod.weight = 45
    return obj


def cube(parent, name, location, dimensions, mat_name="Paint_Dark",
         bevel=0.04, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    attach(obj, parent, location, rotation)
    return finish_mesh(obj, mat_name, min(bevel, min(dimensions) * 0.28), 1)


def cylinder(parent, name, location, radius, depth, mat_name="Steel",
             vertices=16, bevel=0.018, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    obj = bpy.context.object
    obj.name = name
    attach(obj, parent, location, rotation)
    return finish_mesh(obj, mat_name, min(bevel, radius * 0.28), 2, True)


def cylinder_between(parent, name, start, end, radius, mat_name="Steel", vertices=12):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=direction.length)
    obj = bpy.context.object
    obj.name = name
    attach(obj, parent, (start_v + end_v) * 0.5)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    return finish_mesh(obj, mat_name, min(radius * 0.2, 0.02), 2, True)


def cone(parent, name, location, radius_bottom, radius_top, depth,
         mat_name="Steel", vertices=20):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius_bottom, radius2=radius_top, depth=depth
    )
    obj = bpy.context.object
    obj.name = name
    attach(obj, parent, location)
    return finish_mesh(obj, mat_name, 0.018, 2, True)


def torus(parent, name, location, major_radius, minor_radius, mat_name="Steel",
          rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=16, minor_segments=6,
        major_radius=major_radius, minor_radius=minor_radius
    )
    obj = bpy.context.object
    obj.name = name
    attach(obj, parent, location, rotation)
    return finish_mesh(obj, mat_name, 0.008, 1, True)


def inset_panel(parent, name, location, width, height, mat_name="Paint_Orange"):
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (width, height, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    attach(obj, parent, location, (math.pi / 2.0, 0.0, 0.0))
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.inset(thickness=min(0.09, min(width, height) * 0.12), depth=0.0)
    bpy.ops.mesh.extrude_region_move(TRANSFORM_OT_translate={"value": (0.0, 0.0, -0.055)})
    bpy.ops.object.mode_set(mode="OBJECT")
    return finish_mesh(obj, mat_name, 0.008, 2)


def bolt(parent, name, location, mat_name="Steel", radius=0.055, axis="Y"):
    rotation = (math.pi / 2.0, 0.0, 0.0) if axis == "Y" else (0.0, 0.0, 0.0)
    return cylinder(parent, name, location, radius, radius * 0.55, mat_name, 12, 0.006, rotation)


def ladder(parent, center, height, width=0.48, mat_name="Hazard"):
    for side in (-1.0, 1.0):
        cylinder_between(parent, "Ladder_Rail",
                         (center[0] + side * width * 0.5, center[1], center[2]),
                         (center[0] + side * width * 0.5, center[1], center[2] + height),
                         0.035, mat_name, 12)
    for index in range(max(3, int(height / 0.33))):
        z = center[2] + 0.16 + index * 0.33
        cylinder_between(parent, "Ladder_Rung",
                         (center[0] - width * 0.5, center[1], z),
                         (center[0] + width * 0.5, center[1], z),
                         0.028, "Steel", 12)


def vent_bank(parent, center, count=8, width=1.4, mat_name="Paint_Dark"):
    for index in range(count):
        x = center[0] - width * 0.5 + width * index / max(1, count - 1)
        cube(parent, "Vent_Slat", (x, center[1], center[2]),
             (0.07, 0.05, 0.52), mat_name, 0.014, (math.radians(-24), 0.0, 0.0))


def flange_pipe(parent, start, end, radius=0.12, mat_name="Steel"):
    cylinder_between(parent, "Pressure_Pipe", start, end, radius, mat_name, 20)
    for point in (start, end):
        cylinder_between(parent, "Pipe_Flange",
                         (point[0], point[1], point[2] - 0.055),
                         (point[0], point[1], point[2] + 0.055),
                         radius * 1.48, "Hazard", 24)
        for bolt_index in range(6):
            angle = math.tau * bolt_index / 6
            bolt(parent, "Flange_Bolt",
                 (point[0] + math.cos(angle) * radius * 1.25,
                  point[1] + math.sin(angle) * radius * 1.25, point[2]),
                 radius=0.025, axis="Z")


def add_status_light(parent, location):
    light = empty("StatusLight", parent, location)
    cylinder(light, "StatusLens", (0.0, 0.0, 0.0), 0.13, 0.11,
             "Emissive_Status", 16, 0.008)
    return light


def machine_root():
    root = empty("AssetRoot")
    static = empty("Static_Geometry", root)
    return root, static


def join_group(parent, name):
    objects = [child for child in parent.children if child.type == "MESH"]
    if len(objects) < 2:
        if objects:
            objects[0].name = name
        return
    for obj in objects:
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    objects[0].parent = parent
    objects[0].matrix_parent_inverse = Matrix.Identity(4)


def add_frame(parent, width, length, base_z=0.2, beam=0.18, mat_name="Paint_Dark"):
    for x in (-width * 0.5, width * 0.5):
        cube(parent, "Frame_Long_Rail", (x, 0.0, base_z),
             (beam, length, beam), mat_name)
    for y in (-length * 0.5, length * 0.5):
        cube(parent, "Frame_Cross_Rail", (0.0, y, base_z),
             (width, beam, beam), "Steel")
    for x in (-width * 0.43, width * 0.43):
        for y in (-length * 0.43, length * 0.43):
            bolt(parent, "Frame_Bolt", (x, y, base_z + beam * 0.58), "Hazard", 0.05, "Z")


def build_miner():
    root, body = machine_root()
    add_frame(body, 3.7, 3.7, 0.24, 0.2)
    for x in (-1.48, 1.48):
        for y in (-1.42, 1.42):
            cube(body, "Rig_Foot", (x, y, 0.2), (0.55, 0.55, 0.22), "Concrete")
            cylinder(body, "Derrick_Leg", (x, y, 3.15), 0.13, 5.7, "Steel", 18)
            cylinder(body, "Hydraulic_Piston", (x * 0.82, y * 0.82, 2.1),
                     0.08, 2.6, "Hazard", 16)
    for z in (1.05, 2.65, 4.25, 5.7):
        for y in (-1.42, 1.42):
            cube(body, "Tower_Crossbeam", (0.0, y, z), (3.4, 0.16, 0.17), "Steel")
        for x in (-1.48, 1.48):
            cube(body, "Tower_Crossbeam", (x, 0.0, z), (0.16, 3.25, 0.17), "Steel")
    for corner in (-1.0, 1.0):
        cylinder_between(body, "Derrick_Diagonal",
                         (corner * 1.42, -1.42, 1.2),
                         (-corner * 1.42, -1.42, 5.4), 0.065, "Hazard", 12)
    cube(body, "Derrick_Crown", (0.0, 0.0, 6.0), (2.3, 2.2, 0.42), "Paint_Orange")
    cube(body, "Control_Cabinet", (1.92, -0.8, 1.55), (0.7, 1.0, 1.4), "Paint_Orange")
    inset_panel(body, "Control_Cabinet_Door", (1.93, -0.8, 1.65), 0.54, 0.92, "Paint_Dark")
    for z in (1.4, 1.68, 1.96):
        cylinder(body, "Control_Dial", (2.01, -0.8, z), 0.09, 0.055,
                 "Emissive_Status", 16, 0.008, (math.pi / 2, 0.0, 0.0))
    vent_bank(body, (0.0, -1.9, 1.1), 9, 1.6)
    ladder(body, (-1.76, -1.0, 0.4), 4.8)
    for x in (-0.45, 0.0, 0.45):
        cylinder(body, "Chute_Roller", (x - 1.0, -1.86, 0.72), 0.12, 1.1, "Rubber", 16, 0.01, (0.0, math.pi / 2, 0.0))
    cube(body, "Ore_Chute", (-1.0, -0.95, 1.05), (0.9, 2.15, 0.48),
         "Paint_Orange", 0.08, (math.radians(12), 0.0, 0.0))
    cube(body, "Hazard_Skirting", (0.0, -1.9, 0.42), (3.3, 0.12, 0.22), "Hazard")
    drill = empty("Drill", root, (0.0, 0.0, 1.0))
    cylinder(drill, "Drill_Hub", (0.0, 0.0, 0.0), 0.66, 0.48, "Steel", 24)
    cylinder(drill, "Drill_Collar", (0.0, 0.0, -0.34), 0.48, 0.18, "Hazard", 24)
    cone(drill, "Drill_Bit", (0.0, 0.0, -0.9), 0.42, 0.025, 0.95, "Steel", 12)
    for index in range(8):
        angle = math.tau * index / 8
        cylinder_between(drill, "Drill_Flute",
                         (math.cos(angle) * 0.28, math.sin(angle) * 0.28, -1.18),
                         (math.cos(angle) * 0.12, math.sin(angle) * 0.12, -0.52),
                         0.055, "Paint_Orange", 10)
    piston = empty("Piston", root, (0.0, 0.0, 4.15))
    cylinder(piston, "Piston_Barrel", (0.0, 0.0, 0.0), 0.24, 1.8, "Paint_Dark", 20)
    cylinder(piston, "Piston_Rod", (0.0, 0.0, -0.95), 0.105, 0.85, "Steel", 16)
    add_status_light(body, (1.55, -1.6, 5.85))
    return root, (4.0, 4.0, 6.5)


def build_smelter():
    root, body = machine_root()
    add_frame(body, 3.65, 3.65, 0.18, 0.18)
    for x in (-1.36, 1.36):
        for y in (-1.25, 1.25):
            cylinder(body, "Furnace_Leg", (x, y, 0.52), 0.17, 0.7, "Steel", 16)
    cylinder(body, "Furnace_Belly", (0.0, 0.0, 1.35), 1.42, 2.05, "Paint_Dark", 12, 0.06)
    for z, radius in ((0.52, 1.5), (0.72, 1.48), (2.25, 1.48), (2.42, 1.37)):
        torus(body, "Furnace_Armor_Ring", (0.0, 0.0, z), radius, 0.075, "Steel")
    for index in range(12):
        angle = math.tau * index / 12
        x, y = math.cos(angle) * 1.43, math.sin(angle) * 1.43
        cylinder(body, "Furnace_Rivet", (x, y, 1.4), 0.075, 0.07, "Hazard", 12, 0.006,
                 (math.pi / 2, 0.0, angle))
    cube(body, "Furnace_Front_Fascia", (0.0, -1.43, 1.4), (1.9, 0.25, 1.2), "Paint_Orange", 0.09)
    inset_panel(body, "Furnace_Service_Panel", (0.0, -1.57, 1.7), 1.4, 0.58, "Paint_Dark")
    for x in (-0.44, 0.0, 0.44):
        bolt(body, "Service_Panel_Bolt", (x, -1.61, 1.93), "Hazard", 0.045)
    cube(body, "Furnace_Mouth_Rim", (0.0, -1.6, 0.97), (1.22, 0.22, 0.72), "Hazard")
    glow = empty("Furnace_Glow", root, (0.0, -1.74, 0.98))
    cube(glow, "Furnace_Glow_Mesh", (0.0, 0.0, 0.0), (0.82, 0.08, 0.42), "Emissive_Furnace")
    cube(body, "Crucible_Housing", (0.0, 0.0, 2.62), (2.8, 2.8, 0.46), "Paint_Orange")
    cone(body, "Top_Hopper", (0.0, 0.0, 3.15), 0.68, 0.38, 0.65, "Steel", 12)
    cylinder(body, "Hopper_Rim", (0.0, 0.0, 3.51), 0.72, 0.11, "Hazard", 20)
    cylinder(body, "Chimney", (0.85, 0.65, 3.55), 0.28, 2.1, "Steel", 20)
    for z in (2.62, 4.32):
        torus(body, "Chimney_Flange", (0.85, 0.65, z), 0.36, 0.07, "Hazard")
    torus(body, "Chimney_Elbow", (0.6, 0.65, 4.25), 0.23, 0.07, "Steel", (math.pi / 2, 0.0, 0.0))
    for x in (-1.2, -0.85, 0.85, 1.2):
        vent_bank(body, (x, -1.52, 1.5), 4, 0.36, "Steel")
    add_status_light(body, (1.35, -1.65, 2.4))
    return root, (4.0, 4.0, 5.0)


def build_constructor():
    root, body = machine_root()
    add_frame(body, 3.55, 5.55, 0.2, 0.2)
    for side in (-1.0, 1.0):
        x = side * 1.65
        cube(body, "Constructor_Side_Wall", (x, 0.0, 1.55), (0.22, 4.7, 2.75), "Paint_Orange")
        for y in (-1.4, 0.0, 1.4):
            cube(body, "Window_Frame", (x - side * 0.13, y, 1.75), (0.11, 1.1, 0.9), "Steel")
            cube(body, "Inspection_Glass", (x - side * 0.205, y, 1.75), (0.05, 0.82, 0.62), "Glass", 0.025)
        for z in (0.52, 0.82, 2.55, 2.83):
            cube(body, "Housing_Rib", (x - side * 0.14, 0.0, z), (0.16, 4.6, 0.085), "Hazard" if z < 0.9 else "Paint_Dark")
    cube(body, "Roof_Spine", (0.0, 0.0, 3.18), (3.0, 5.45, 0.28), "Paint_Dark")
    for y in (-2.2, -1.45, -0.7, 0.05, 0.8, 1.55, 2.25):
        cube(body, "Roof_Rib", (0.0, y, 3.33), (3.5, 0.12, 0.18), "Steel")
    for end in (-1.0, 1.0):
        cube(body, "Conveyor_Mouth", (-1.0, end * 2.82, 0.48), (1.55, 0.58, 0.74), "Paint_Dark")
        for flap_x in (-0.54, -0.18, 0.18, 0.54):
            cube(body, "Rubber_Flap", (-1.0 + flap_x, end * 2.56, 0.24), (0.16, 0.08, 0.46), "Rubber")
        cube(body, "Mouth_Hazard", (-1.0, end * 2.84, 0.91), (1.65, 0.12, 0.14), "Hazard")
    press = empty("Press", root, (0.0, 0.0, 2.5))
    cube(press, "Press_Carriage", (0.0, 0.0, 0.0), (1.4, 1.25, 0.38), "Paint_Orange")
    cylinder(press, "Press_Ram", (0.0, 0.0, -0.58), 0.18, 0.9, "Steel", 20)
    cube(press, "Press_Die", (0.0, 0.0, -1.08), (1.1, 0.9, 0.2), "Hazard")
    for x in (-1.15, 1.15):
        cylinder(body, "Gantry_Guide", (x, 0.0, 2.15), 0.075, 1.6, "Steel", 16)
    vent_bank(body, (0.0, -1.8, 2.9), 12, 2.2)
    for y in (-2.0, 2.0):
        for x in (-1.4, 1.4):
            bolt(body, "Housing_Bolt", (x, y, 2.75), "Hazard", 0.052, "Z")
    add_status_light(body, (1.54, -2.1, 3.05))
    return root, (4.0, 6.0, 3.8)


def build_assembler():
    root, body = machine_root()
    add_frame(body, 5.55, 5.55, 0.22, 0.22)
    for x in (-2.5, 2.5):
        for y in (-2.45, 2.45):
            cube(body, "Assembler_Pylon", (x, y, 2.05), (0.34, 0.34, 3.6), "Steel")
    for x in (-2.5, 2.5):
        for z in (0.72, 3.55):
            cube(body, "Assembler_Side_Rail", (x, 0.0, z), (0.34, 5.1, 0.26), "Paint_Orange")
    for y in (-2.45, 2.45):
        cube(body, "Assembler_End_Rail", (0.0, y, 3.55), (5.1, 0.3, 0.25), "Paint_Dark")
    cube(body, "Assembler_Roof_Rack", (0.0, 0.0, 3.8), (5.0, 5.0, 0.2), "Steel")
    for y in (-1.8, -0.9, 0.0, 0.9, 1.8):
        cube(body, "Roof_Rib", (0.0, y, 3.96), (5.05, 0.12, 0.14), "Paint_Orange")
    for side in (-1.0, 1.0):
        cube(body, "Inspection_Glass", (side * 2.43, 0.0, 2.18), (0.06, 3.9, 1.75), "Glass", 0.03)
    for x in (-1.4, 1.4):
        cone(body, "Input_Hopper", (x, -1.5, 3.1), 0.66, 0.34, 0.85, "Hazard", 16)
        torus(body, "Hopper_Lip", (x, -1.5, 3.54), 0.6, 0.075, "Steel")
    for index, x in enumerate((-1.15, 1.15)):
        arm = empty("Arm_A" if index == 0 else "Arm_B", root, (x, 0.25, 2.15))
        cylinder(arm, "Robot_Base", (0.0, 0.0, 0.0), 0.28, 0.38, "Paint_Dark", 20)
        cylinder_between(arm, "Robot_Upper_Link", (0.0, 0.0, 0.15), (0.0, -0.65, 0.72),
                         0.14, "Paint_Orange", 16)
        cylinder_between(arm, "Robot_Forearm", (0.0, -0.65, 0.72), (0.0, -1.35, 0.35),
                         0.1, "Steel", 16)
        cube(arm, "Robot_Gripper", (0.0, -1.38, 0.2), (0.42, 0.22, 0.16), "Hazard")
        for claw_x in (-0.16, 0.16):
            cube(arm, "Robot_Gripper_Finger", (claw_x, -1.52, 0.05), (0.08, 0.32, 0.16), "Steel")
    cube(body, "Assembler_Belt_Mouth", (0.0, -2.8, 0.48), (1.4, 0.48, 0.66), "Rubber")
    cube(body, "Mouth_Hazard", (0.0, -2.8, 0.86), (1.5, 0.12, 0.1), "Hazard")
    for x in (-2.0, 2.0):
        cube(body, "Assembler_Belt_Mouth", (x, 2.8, 0.48), (1.0, 0.48, 0.66), "Rubber")
        cube(body, "Mouth_Hazard", (x, 2.8, 0.86), (1.1, 0.12, 0.1), "Hazard")
    vent_bank(body, (2.66, 0.0, 1.8), 14, 2.6)
    add_status_light(body, (2.54, -2.4, 3.35))
    return root, (6.0, 6.0, 4.2)


def build_geo_tap():
    root, body = machine_root()
    add_frame(body, 3.7, 3.7, 0.24, 0.2)
    cylinder(body, "Wellhead_Collar", (0.0, 0.0, 0.55), 1.08, 0.36, "Hazard", 24)
    cylinder(body, "Wellhead_Main", (0.0, 0.0, 1.5), 0.78, 1.8, "Steel", 24)
    for z in (0.72, 1.18, 2.05, 2.4):
        torus(body, "Wellhead_Flange", (0.0, 0.0, z), 0.82 if z < 1.6 else 0.64, 0.09, "Paint_Orange")
    for index in range(12):
        angle = math.tau * index / 12
        bolt(body, "Wellhead_Bolt", (math.cos(angle) * 1.02, math.sin(angle) * 1.02, 0.62),
             "Steel", 0.055, "Z")
    for side in (-1.0, 1.0):
        cylinder_between(body, "Steam_Pipe_Leg", (side * 0.8, -0.55, 1.1),
                         (side * 1.38, -0.55, 2.2), 0.15, "Paint_Orange", 20)
        torus(body, "Pipe_Loop", (side * 1.38, -0.55, 2.65), 0.42, 0.14, "Steel",
              (math.pi / 2, 0.0, 0.0))
        flange_pipe(body, (side * 1.38, -0.55, 2.95),
                    (side * 1.38, -0.55, 3.42), 0.13, "Paint_Orange")
    cube(body, "Turbine_Housing", (0.0, -1.23, 3.12), (1.65, 0.82, 1.08), "Paint_Dark")
    torus(body, "Turbine_Rim", (0.0, -1.68, 3.14), 0.48, 0.09, "Hazard",
          (math.pi / 2, 0.0, 0.0))
    turbine = empty("Turbine", root, (0.0, -1.78, 3.14))
    cylinder(turbine, "Turbine_Axle", (0.0, 0.0, 0.0), 0.15, 0.42, "Steel", 20,
             rotation=(math.pi / 2, 0.0, 0.0))
    for index in range(8):
        angle = math.tau * index / 8
        cube(turbine, "Turbine_Blade",
             (math.cos(angle) * 0.24, 0.0, math.sin(angle) * 0.24),
             (0.16, 0.08, 0.38), "Paint_Orange", 0.035,
             (0.0, angle, math.radians(24)))
    cylinder(body, "Steam_Vent", (0.0, 0.0, 3.7), 0.32, 0.36, "Steel", 20)
    torus(body, "Vent_Grille", (0.0, 0.0, 3.91), 0.26, 0.045, "Hazard")
    add_status_light(body, (1.44, -1.85, 2.9))
    return root, (4.0, 4.0, 4.2)


def build_power_pole():
    root, body = machine_root()
    cube(body, "Pole_Base_Plate", (0.0, 0.0, 0.18), (1.6, 1.6, 0.3), "Concrete")
    cylinder(body, "Tapered_Mast", (0.0, 0.0, 3.0), 0.18, 5.55, "Steel", 20)
    for z in (0.55, 1.85, 3.15, 4.45):
        torus(body, "Mast_Collar", (0.0, 0.0, z), 0.2, 0.045, "Hazard")
    cube(body, "Crossarm", (0.0, 0.0, 5.25), (2.0, 0.18, 0.2), "Paint_Orange")
    cube(body, "Crossarm_Brace", (0.0, 0.0, 4.7), (0.14, 0.14, 1.1), "Steel")
    for x in (-0.8, -0.4, 0.0, 0.4, 0.8):
        cylinder(body, "Ceramic_Insulator", (x, 0.0, 5.62), 0.14, 0.44, "Glass", 16)
        for z in (5.48, 5.6, 5.72):
            torus(body, "Insulator_Glaze", (x, 0.0, z), 0.14, 0.025, "Steel")
    for side in (-1.0, 1.0):
        cylinder_between(body, "Lattice_Brace",
                         (0.0, side * 0.08, 0.75), (side * 0.8, 0.0, 5.18),
                         0.048, "Paint_Dark", 12)
    for x in (-0.75, 0.75):
        for z in (1.0, 2.0, 3.0, 4.0):
            bolt(body, "Crossbolt", (x, -0.12, z), "Hazard", 0.035)
    lamp = empty("StatusLight", root, (0.0, 0.0, 5.95))
    cube(lamp, "Pole_Lamp_Housing", (0.0, 0.0, 0.0), (0.44, 0.4, 0.24), "Paint_Dark")
    cylinder(lamp, "Pole_Lamp_Lens", (0.0, -0.22, 0.0), 0.13, 0.07,
             "Emissive_Status", 16, 0.008, (math.pi / 2, 0.0, 0.0))
    return root, (1.7, 1.7, 6.3)


def build_storage():
    root, body = machine_root()
    add_frame(body, 3.7, 3.7, 0.2, 0.2, "Steel")
    cube(body, "Container_Core", (0.0, 0.0, 1.55), (3.4, 3.4, 2.65), "Paint_Dark")
    for side in (-1.0, 1.0):
        for index in range(11):
            y = -1.48 + index * 0.296
            cube(body, "Corrugation", (side * 1.77, y, 1.53), (0.13, 0.12, 2.42), "Paint_Orange")
    for side in (-1.0, 1.0):
        for index in range(11):
            x = -1.48 + index * 0.296
            cube(body, "Corrugation", (x, side * 1.77, 1.53), (0.12, 0.13, 2.42), "Paint_Orange")
    for x in (-1.72, 1.72):
        for y in (-1.72, 1.72):
            cube(body, "Corner_Post", (x, y, 1.55), (0.26, 0.26, 2.95), "Steel")
            cube(body, "Corner_Cap", (x, y, 3.05), (0.4, 0.4, 0.14), "Hazard")
    cube(body, "Hatch_Frame", (0.0, -1.84, 1.6), (1.82, 0.16, 1.9), "Hazard")
    inset_panel(body, "Hatch_Recess", (0.0, -1.94, 1.6), 1.5, 1.55, "Steel")
    for x in (-0.52, 0.52):
        cylinder(body, "Hatch_Hinge", (x, -2.0, 2.0), 0.08, 0.52, "Steel", 16,
                 rotation=(math.pi / 2, 0.0, 0.0))
    ladder(body, (-1.93, -1.4, 0.2), 2.85, 0.52)
    for z in (0.46, 2.82):
        cube(body, "Container_Strapping", (0.0, -1.86, z), (3.55, 0.12, 0.13), "Hazard")
    cube(body, "Roof_Hatch", (0.0, 0.0, 3.04), (1.0, 1.0, 0.18), "Steel")
    add_status_light(body, (1.5, -1.85, 2.8))
    return root, (4.0, 4.0, 3.4)


def build_junction(kind):
    root, body = machine_root()
    add_frame(body, 1.75, 1.75, 0.2, 0.12)
    cube(body, "Junction_Armor", (0.0, 0.0, 0.78), (1.45, 1.45, 1.15), "Paint_Orange")
    for z in (0.32, 1.23):
        cube(body, "Hazard_Band", (0.0, 0.0, z), (1.55, 1.55, 0.12), "Hazard")
    ports = [((0.0, -1.0), 1.0), ((-1.0, 0.0), 0.0), ((1.0, 0.0), 0.0)]
    if kind == "merger":
        ports = [((0.0, 1.0), 1.0), ((-1.0, 0.0), 0.0), ((1.0, 0.0), 0.0)]
    for (dx, dy), _unused in ports:
        if dy:
            loc = (0.0, dy * 0.95, 0.62)
            dims = (0.84, 0.76, 0.62)
        else:
            loc = (dx * 0.95, 0.0, 0.62)
            dims = (0.76, 0.84, 0.62)
        cube(body, "Belt_Mouth", loc, dims, "Rubber")
        cube(body, "Mouth_Lip", (loc[0], loc[1], 0.98), (dims[0] + 0.06, dims[1] + 0.06, 0.11), "Steel")
    cube(body, "Flow_Arrow_Shaft", (0.0, 0.0, 1.48), (0.13, 0.62, 0.08), "Hazard")
    for side in (-1.0, 1.0):
        cube(body, "Flow_Arrow_Head", (side * 0.22, 0.0, 1.48),
             (0.11, 0.26, 0.08), "Hazard", 0.02, (0.0, 0.0, side * math.radians(38)))
    for x in (-0.48, 0.48):
        for y in (-0.48, 0.48):
            bolt(body, "Junction_Bolt", (x, y, 1.42), "Steel", 0.045, "Z")
    for x in (-0.58, 0.58):
        bolt(body, "Armor_Fastener", (x, 0.0, 1.4), "Hazard", 0.04, "Z")
    add_status_light(body, (0.0, 0.0, 1.72))
    return root, (1.8, 1.8, 1.9)


def build_belt():
    root, body = machine_root()
    add_frame(body, 1.7, 1.8, 0.17, 0.12, "Steel")
    belt = empty("Belt", root, (0.0, 0.0, 0.32))
    cube(belt, "Belt_Surface", (0.0, 0.0, 0.0), (1.45, 1.55, 0.12), "Rubber", 0.025)
    for side in (-1.0, 1.0):
        cube(body, "Side_Rail", (side * 0.79, 0.0, 0.44), (0.12, 1.72, 0.36), "Paint_Dark")
        cube(body, "Rail_Hazard", (side * 0.79, 0.0, 0.64), (0.1, 1.74, 0.07), "Hazard")
    for y in (-0.72, 0.72):
        cylinder(body, "End_Roller", (0.0, y, 0.26), 0.15, 1.45, "Steel", 20,
                 0.015, (0.0, math.pi / 2.0, 0.0))
    for x in (-0.58, 0.58):
        for y in (-0.55, 0.55):
            cube(body, "Support_Leg", (x, y, -0.02), (0.13, 0.13, 0.5), "Steel")
            cube(body, "Foot_Plate", (x, y, -0.27), (0.34, 0.28, 0.1), "Concrete")
    for side in (-1.0, 1.0):
        for y in (-0.58, -0.18, 0.22, 0.62):
            bolt(body, "Rail_Bolt", (side * 0.87, y, 0.49), "Hazard", 0.035, "Z")
    return root, (1.9, 1.9, 0.9)


def build_hub():
    root, body = machine_root()
    add_frame(body, 3.8, 2.8, 0.25, 0.2, "Steel")
    cube(body, "HUB_Hull", (0.0, 0.0, 1.45), (3.45, 2.5, 2.45), "Paint_Dark")
    cube(body, "HUB_Armor_Front", (0.0, -1.32, 1.35), (3.2, 0.14, 1.85), "Paint_Orange")
    inset_panel(body, "HUB_Terminal_Screen", (0.0, -1.43, 1.85), 1.82, 0.88, "Glass")
    cube(body, "HUB_Screen_Bezel", (0.0, -1.48, 1.85), (2.1, 0.12, 1.12), "Steel")
    for side in (-1.0, 1.0):
        cube(body, "HUB_Corner_Rib", (side * 1.55, 0.0, 1.55), (0.18, 2.48, 2.1), "Hazard")
        cylinder(body, "HUB_Antenna", (side * 1.45, 0.72, 3.05), 0.045, 1.15, "Steel", 12)
    for y in (-0.85, -0.28, 0.28, 0.85):
        cube(body, "HUB_Roof_Rib", (0.0, y, 2.75), (3.2, 0.11, 0.2), "Steel")
    cube(body, "HUB_Ramp", (0.0, -2.05, 0.38), (1.9, 1.25, 0.2), "Steel",
         0.035, (math.radians(12), 0.0, 0.0))
    for side in (-1.0, 1.0):
        cylinder_between(body, "Ramp_Railing", (side * 1.02, -2.48, 0.6),
                         (side * 1.02, -1.55, 1.25), 0.035, "Hazard", 12)
    for x in (-0.72, 0.72):
        cylinder(body, "Terminal_Knob", (x, -1.52, 1.1), 0.08, 0.08, "Emissive_Status",
                 16, 0.008, (math.pi / 2, 0.0, 0.0))
    add_status_light(body, (1.42, -1.53, 2.55))
    return root, (4.0, 3.0, 3.5)


def build_drop_pod():
    root, body = machine_root()
    cylinder(body, "Pod_Central_Cylinder", (0.0, 0.0, 1.55), 1.23, 3.25, "Paint_Dark", 24)
    for z in (0.17, 0.44, 2.7, 2.96):
        torus(body, "Pod_Reinforcement_Band", (0.0, 0.0, z), 1.25, 0.12, "Hazard")
    for end_z in (0.05, 3.05):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.22)
        cap = bpy.context.object
        cap.name = "Pod_Capsule_End"
        cap.scale = (1.0, 1.0, 0.8)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        attach(cap, body, (0.0, 0.0, end_z))
        finish_mesh(cap, "Steel", 0.025, 2, True)
    for side in (-1.0, 1.0):
        for y in (-0.7, 0.0, 0.7):
            cylinder_between(body, "Landing_Strut",
                             (side * 0.86, y, 0.58), (side * 1.65, y, 0.08),
                             0.11, "Steel", 16)
            cube(body, "Landing_Foot", (side * 1.68, y, 0.06), (0.52, 0.42, 0.12), "Concrete")
    cube(body, "Pod_Service_Hatch", (0.0, -1.2, 1.55), (0.9, 0.12, 1.0), "Paint_Orange")
    inset_panel(body, "Pod_Hatch_Recess", (0.0, -1.29, 1.55), 0.68, 0.72, "Paint_Dark")
    for x in (-0.72, 0.72):
        cylinder(body, "Porthole_Rim", (x, -1.12, 2.05), 0.19, 0.1, "Hazard", 20,
                 0.008, (math.pi / 2, 0.0, 0.0))
        cylinder(body, "Porthole_Glass", (x, -1.19, 2.05), 0.13, 0.04, "Glass", 20,
                 0.005, (math.pi / 2, 0.0, 0.0))
    cylinder(body, "Pod_Antenna", (0.0, 0.0, 3.55), 0.045, 0.9, "Steel", 12)
    add_status_light(body, (0.0, -1.24, 0.94))
    return root, (4.0, 4.0, 4.4)


def build_spire():
    root, body = machine_root()
    add_frame(body, 11.4, 11.4, 0.24, 0.36, "Concrete")
    for x in (-5.1, 5.1):
        for y in (-5.1, 5.1):
            cylinder(body, "Spire_Leg", (x, y, 8.0), 0.33, 15.5, "Paint_Dark", 16)
            for z in (1.0, 5.2, 9.5, 13.8):
                torus(body, "Spire_Leg_Collar", (x, y, z), 0.38, 0.08, "Hazard")
    for z in (3.3, 8.0, 12.8):
        for side in (-1.0, 1.0):
            cube(body, "Spire_Gantry", (0.0, side * 5.1, z), (10.4, 0.32, 0.36), "Hazard")
            cube(body, "Spire_Gantry", (side * 5.1, 0.0, z), (0.32, 10.4, 0.36), "Steel")
    for x in (-1.3, 1.3):
        for y in (-1.3, 1.3):
            cylinder(body, "Spire_Core_Pylon", (x, y, 7.5), 0.22, 14.6, "Steel", 16)
    for index in range(4):
        angle = math.tau * index / 4
        cylinder_between(body, "Spire_Cross_Brace",
                         (math.cos(angle) * 4.9, math.sin(angle) * 4.9, 1.2),
                         (-math.cos(angle) * 4.9, -math.sin(angle) * 4.9, 14.4),
                         0.075, "Steel", 12)
    ladder(body, (-4.8, -5.5, 0.5), 12.0, 0.58)
    for side in (-1.0, 1.0):
        cylinder(body, "Beacon_Mast", (side * 4.8, 0.0, 15.2), 0.065, 2.0, "Hazard", 16)
    add_status_light(body, (0.0, -5.6, 13.8))
    return root, (12.0, 12.0, 17.0)


def make_leaf_tier(name, parent, center_z, radius, height, seed):
    rng = random.Random(seed)
    segments = 20
    rings = 7
    vertices = []
    faces = []
    for ring in range(rings):
        t = ring / (rings - 1)
        ring_radius = radius * (1.0 - t) ** 0.77
        for segment in range(segments):
            angle = math.tau * segment / segments
            jag = 1.0 + 0.13 * math.sin(angle * 5.0 + seed) + rng.uniform(-0.055, 0.055)
            z_jitter = 0.08 * math.sin(angle * 3.0 + t * 8.0)
            vertices.append((math.cos(angle) * ring_radius * jag,
                             math.sin(angle) * ring_radius * jag,
                             center_z - height * 0.5 + t * height + z_jitter))
    for ring in range(rings - 1):
        for segment in range(segments):
            a = ring * segments + segment
            b = ring * segments + (segment + 1) % segments
            c = (ring + 1) * segments + (segment + 1) % segments
            d = (ring + 1) * segments + segment
            faces.append((a, b, c, d))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material("Foliage"))
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    attach(obj, parent, (0.0, 0.0, 0.0))
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mod = obj.modifiers.new("Leaf_Edge_Bevel", "BEVEL")
    mod.width = 0.018
    mod.segments = 2
    obj.modifiers.new("Leaf_Weighted_Normals", "WEIGHTED_NORMAL")
    return obj


def build_conifer(variant):
    root = empty("AssetRoot")
    height = (12.0, 15.8, 19.5)[variant]
    trunk = empty("Trunk", root)
    canopy = empty("Canopy", root)
    cylinder(trunk, "Conifer_Trunk", (0.0, 0.0, height * 0.39),
             0.27 + variant * 0.035, height * 0.78, "Bark", 16, 0.025)
    for index in range(5):
        z = 0.65 + index * 0.43
        for side in (-1.0, 1.0):
            cylinder_between(trunk, "Root_Buttress",
                             (side * (0.75 + index * 0.04), 0.0, 0.12),
                             (side * 0.08, 0.0, z), 0.06, "Bark", 10)
    tiers = 7 if variant != 1 else 8
    for index in range(tiers):
        fraction = index / max(1, tiers - 1)
        z = height * (0.24 + fraction * 0.69)
        radius = (2.65 + variant * 0.15) * (1.0 - fraction * 0.72)
        tier_height = height * (0.26 if index == 0 else 0.22)
        make_leaf_tier("Conifer_Tier_%02d" % index, canopy, z, radius, tier_height,
                       100 + variant * 31 + index)
    for z in (height * 0.35, height * 0.55, height * 0.73):
        for index in range(8):
            angle = math.tau * index / 8
            cylinder_between(trunk, "Branch_Twig",
                             (math.cos(angle) * 0.2, math.sin(angle) * 0.2, z - 0.8),
                             (math.cos(angle) * 1.4, math.sin(angle) * 1.4, z),
                             0.055, "Bark", 8)
    return root, (5.6 + variant * 0.3, 5.6 + variant * 0.3, height)


def build_broadleaf(variant):
    root = empty("AssetRoot")
    height = (8.8, 11.7, 14.5)[variant]
    trunk = empty("Trunk", root)
    canopy = empty("Canopy", root)
    cylinder(trunk, "Broadleaf_Trunk", (0.0, 0.0, height * 0.38),
             0.38 + variant * 0.05, height * 0.76, "Bark", 18, 0.035)
    for index in range(8):
        angle = math.tau * index / 8
        z = height * (0.55 + (index % 3) * 0.07)
        end = (math.cos(angle) * (2.3 + variant * 0.2),
               math.sin(angle) * (2.3 + variant * 0.2),
               z + height * 0.1)
        cylinder_between(trunk, "Broadleaf_Branch",
                         (0.0, 0.0, z - 0.2), end, 0.12, "Bark", 12)
    rng = random.Random(811 + variant * 77)
    for index in range(14 + variant * 2):
        angle = math.tau * index / (14 + variant * 2)
        radius = rng.uniform(0.75, 2.6 + variant * 0.2)
        z = height * rng.uniform(0.53, 0.9)
        size = rng.uniform(0.85, 1.38)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0)
        blob = bpy.context.object
        blob.name = "Broadleaf_Canopy_Cluster"
        for vertex in blob.data.vertices:
            factor = 1.0 + rng.uniform(-0.15, 0.15)
            vertex.co *= factor
        blob.scale = (size * 1.22, size, size * 0.78)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        attach(blob, canopy, (math.cos(angle) * radius, math.sin(angle) * radius, z))
        finish_mesh(blob, "Foliage", 0.018, 2, True)
    return root, (6.4 + variant * 0.35, 6.4 + variant * 0.35, height)


def build_grass(variant):
    rng = random.Random(924 + variant * 91)
    vertices = []
    faces = []
    colors = []
    blade_count = (7, 9, 8)[variant]
    for blade in range(blade_count):
        angle = math.tau * blade / blade_count + rng.uniform(-0.25, 0.25)
        direction = Vector((math.cos(angle), math.sin(angle)))
        side = Vector((-direction.y, direction.x))
        height = rng.uniform(0.3, 0.58) * (0.94 + variant * 0.04)
        width = rng.uniform(0.035, 0.065)
        bend = rng.uniform(0.06, 0.19)
        base_radius = rng.uniform(0.0, 0.15)
        start_index = len(vertices)
        for row in range(5):
            t = row / 4.0
            center = direction * (base_radius + bend * t * t) + Vector((0.0, 0.0))
            h = height * t
            half_width = width * (1.0 - t) ** 0.8
            for side_sign in (-1.0, 1.0):
                xy = center + side * half_width * side_sign
                vertices.append((xy.x, xy.y, h))
                hue = rng.uniform(-0.07, 0.08)
                base = (0.055 + hue * 0.2, 0.13 + hue * 0.28, 0.035 + hue * 0.1)
                tip_mix = t * 0.72
                tip = (0.3 + hue * 0.3, 0.48 + hue * 0.35, 0.12 + hue * 0.15)
                colors.append(tuple(base[i] * (1.0 - tip_mix) + tip[i] * tip_mix for i in range(3)) + (1.0,))
        for row in range(4):
            a = start_index + row * 2
            faces.append((a, a + 1, a + 3, a + 2))
    mesh = bpy.data.meshes.new("Grass_Clump_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material("GrassBlade"))
    color_attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    for index, color in enumerate(colors):
        color_attr.data[index].color = color
    mesh.color_attributes.active_color = color_attr
    mesh.update()
    root = empty("AssetRoot")
    blade_obj = bpy.data.objects.new("Grass_Clump", mesh)
    bpy.context.collection.objects.link(blade_obj)
    attach(blade_obj, root, (0.0, 0.0, 0.0))
    return root, (0.8, 0.8, 0.62)


def build_hands():
    root = empty("Hands")
    for hand_name, side in (("Hand_L", -1.0), ("Hand_R", 1.0)):
        hand = empty(hand_name, root, (side * 0.28, 0.0, 0.0))
        cylinder(hand, "Sleeve_Orange", (0.0, 0.03, -0.07), 0.12, 0.38,
                 "Paint_Orange", 16, 0.025, (math.pi / 2, 0.0, 0.0))
        torus(hand, "Sleeve_Cuff_Seam", (0.0, 0.22, -0.02), 0.12, 0.018,
              "Steel", (math.pi / 2, 0.0, 0.0))
        cube(hand, "Wrist_Cuff", (0.0, 0.25, -0.02), (0.31, 0.13, 0.23),
             "Paint_Dark", 0.035)
        cube(hand, "Cuff_Ridge", (0.0, 0.25, 0.08), (0.27, 0.07, 0.035),
             "Steel", 0.012)
        cube(hand, "Glove_Palm", (0.0, 0.39, 0.12), (0.26, 0.24, 0.17),
             "Rubber", 0.045)
        cube(hand, "Palm_Pad", (0.0, 0.39, 0.21), (0.19, 0.18, 0.035),
             "Paint_Dark", 0.018)
        for finger in range(4):
            x = (finger - 1.5) * 0.062
            finger_length = 0.11 if finger in (0, 3) else 0.14
            cube(hand, "Finger_%d_Base" % finger,
                 (x, 0.52 + finger_length * 0.18, 0.12),
                 (0.052, finger_length * 0.62, 0.072), "Rubber", 0.018)
            cube(hand, "Finger_%d_Knuckle" % finger,
                 (x, 0.52 + finger_length * 0.57, 0.14),
                 (0.048, 0.045, 0.078), "Paint_Dark", 0.012)
            cube(hand, "Finger_%d_Tip" % finger,
                 (x, 0.52 + finger_length * 0.88, 0.11),
                 (0.048, finger_length * 0.3, 0.064), "Rubber", 0.018)
        cube(hand, "Thumb_Base", (side * 0.15, 0.37, 0.11),
             (0.085, 0.14, 0.09), "Rubber", 0.025,
             (0.0, 0.0, side * 0.42))
        cube(hand, "Thumb_Pad", (side * 0.19, 0.45, 0.12),
             (0.07, 0.09, 0.08), "Paint_Dark", 0.02,
             (0.0, 0.0, side * 0.36))
        for finger in range(4):
            x = (finger - 1.5) * 0.062
            cube(hand, "Knuckle_Plate_%d" % finger,
                 (x, 0.5, 0.21), (0.044, 0.065, 0.025),
                 "Paint_Dark", 0.01)
        for obj in hand.children:
            if obj.type == "MESH":
                for modifier in obj.modifiers:
                    if modifier.type == "BEVEL":
                        modifier.segments = 3
    return root, (1.45, 1.0, 0.75)


def build_hand_pick():
    root = empty("HandPick")
    cylinder(root, "Pick_Handle", (0.0, 0.0, -0.2), 0.035, 0.62,
             "Paint_Dark", 16, 0.012)
    cylinder(root, "Pick_Grip", (0.0, -0.01, -0.2), 0.052, 0.26,
             "Rubber", 16, 0.012)
    cube(root, "Pick_Head", (0.0, 0.0, 0.15), (0.36, 0.085, 0.12),
         "Steel", 0.035)
    cube(root, "Pick_Tip_L", (-0.19, 0.0, 0.15), (0.12, 0.075, 0.07),
         "Paint_Dark", 0.025, (0.0, 0.0, -0.3))
    cube(root, "Pick_Tip_R", (0.19, 0.0, 0.15), (0.12, 0.075, 0.07),
         "Paint_Dark", 0.025, (0.0, 0.0, 0.3))
    return root, (0.52, 0.52, 0.52)

def build_tool():
    root = empty("BuildTool")
    body = empty("Tool_Body", root)
    cube(body, "Tool_Grip", (0.0, 0.02, -0.18), (0.15, 0.22, 0.28),
         "Paint_Dark", 0.035, (math.radians(-9), 0.0, 0.0))
    cube(body, "Grip_Rubber_Pad", (0.0, 0.015, -0.2), (0.158, 0.12, 0.2),
         "Rubber", 0.028, (math.radians(-9), 0.0, 0.0))
    cube(body, "Tool_Shell", (0.0, 0.18, 0.045), (0.3, 0.42, 0.23),
         "Paint_Orange", 0.065)
    cube(body, "Tool_Armor_Plate", (0.0, 0.17, 0.17), (0.22, 0.31, 0.035),
         "Paint_Dark", 0.025)
    cube(body, "Tool_Screen_Bezel", (0.0, -0.045, 0.11), (0.18, 0.035, 0.14),
         "Paint_Dark", 0.018)
    screen = empty("ToolScreen", body, (0.0, -0.066, 0.11))
    cube(screen, "Screen_Surface", (0.0, 0.0, 0.0), (0.14, 0.008, 0.105),
         "Glass", 0.005)
    cube(body, "Tool_Screen_Status", (0.105, -0.051, 0.16),
         (0.025, 0.018, 0.025), "Emissive_Status", 0.006)
    cube(body, "Tool_Trigger", (0.0, 0.0, -0.035), (0.075, 0.12, 0.06),
         "Steel", 0.018, (math.radians(-18), 0.0, 0.0))
    cylinder(body, "Emitter_Housing", (0.0, 0.43, 0.045), 0.12, 0.16,
             "Paint_Dark", 20, 0.018, (-math.pi / 2, 0.0, 0.0))
    torus(body, "Emitter_Rim", (0.0, 0.51, 0.045), 0.105, 0.025,
          "Steel", (math.pi / 2, 0.0, 0.0))
    cylinder(body, "EmitterTip", (0.0, 0.525, 0.045), 0.075, 0.045,
             "Emissive_Status", 20, 0.006, (-math.pi / 2, 0.0, 0.0))
    for side in (-1.0, 1.0):
        cube(body, "Shell_Rail", (side * 0.145, 0.19, 0.03),
             (0.035, 0.3, 0.15), "Steel", 0.012)
        for y in (0.08, 0.21, 0.34):
            bolt(body, "Tool_Bolt", (side * 0.165, y, 0.09),
                 "Hazard", 0.018, "X")
    cube(body, "Battery_Pack", (0.0, -0.08, -0.12), (0.22, 0.16, 0.1),
         "Paint_Dark", 0.025)
    for x in (-0.065, 0.0, 0.065):
        cube(body, "Battery_Rib", (x, -0.08, -0.065), (0.025, 0.1, 0.015),
             "Steel", 0.005)
    return root, (0.5, 0.8, 0.7)


BUILDERS = {
    "miner_mk1": build_miner,
    "smelter": build_smelter,
    "constructor": build_constructor,
    "assembler": build_assembler,
    "geo_tap": build_geo_tap,
    "power_pole": build_power_pole,
    "storage": build_storage,
    "splitter": lambda: build_junction("splitter"),
    "merger": lambda: build_junction("merger"),
    "belt": build_belt,
    "hub": build_hub,
    "drop_pod": build_drop_pod,
    "hand_pick": build_hand_pick,
    "ascent_spire": build_spire,
    "tree_conifer_01": lambda: build_conifer(0),
    "tree_conifer_02": lambda: build_conifer(1),
    "tree_conifer_03": lambda: build_conifer(2),
    "tree_broadleaf_01": lambda: build_broadleaf(0),
    "tree_broadleaf_02": lambda: build_broadleaf(1),
    "tree_broadleaf_03": lambda: build_broadleaf(2),
    "grass_clump_01": lambda: build_grass(0),
    "grass_clump_02": lambda: build_grass(1),
    "grass_clump_03": lambda: build_grass(2),
    "hands": build_hands,
    "build_tool": build_tool,
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def prepare_preview(camera_target, max_dimension):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.display.shading.light = "STUDIO"
    scene.display.shading.studio_light = "paint.sl"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.curvature_ridge_factor = 1.2
    scene.display.shading.curvature_valley_factor = 0.8
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (0.075, 0.085, 0.075)
    data = bpy.data.cameras.new("Turntable_Camera")
    camera = bpy.data.objects.new("Turntable_Camera", data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    data.type = "ORTHO"
    data.ortho_scale = max_dimension * 1.9
    camera.location = (max_dimension * 1.25, -max_dimension * 1.85,
                       camera_target[2] + max_dimension * 0.9)
    direction = Vector(camera_target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return camera


def model_triangles(objects):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    total = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        total += sum(max(1, len(poly.vertices) - 2) for poly in mesh.polygons)
        evaluated.to_mesh_clear()
    return total


PORT_FOOTPRINTS = {
    "miner_mk1": (2, 2),
    "smelter": (2, 2),
    "constructor": (2, 3),
    "assembler": (3, 3),
    "geo_tap": (2, 2),
    "storage": (2, 2),
    "splitter": (1, 1),
    "merger": (1, 1),
    "belt": (1, 1),
    "ascent_spire": (6, 6),
}


def _port_specs(kind):
    size = PORT_FOOTPRINTS.get(kind)
    if kind == "power_pole":
        return [
            {"name": "Port_In_0", "position": (-1.0, 0.0), "direction": (-1, 0), "height": 5.62},
            {"name": "Port_Out_0", "position": (1.0, 0.0), "direction": (1, 0), "height": 5.62},
        ]
    if kind in ("hub", "drop_pod"):
        front_y, back_y = (-1.5, 1.5) if kind == "hub" else (-1.25, 1.25)
        height = 0.55 if kind == "hub" else 1.05
        return [
            {"name": "Port_In_0", "position": (0.0, back_y), "direction": (0, -1), "height": height},
            {"name": "Port_Out_0", "position": (0.0, front_y), "direction": (0, 1), "height": height},
        ]
    if kind == "ascent_spire":
        return [
            {"name": "Port_In_0", "cell": (1, 6), "direction": (0, 1), "height": 0.72, "mouth": True, "simple_mouth": True, "width": 0.82},
            {"name": "Port_In_1", "cell": (4, 6), "direction": (0, 1), "height": 0.72, "mouth": True, "simple_mouth": True, "width": 0.82},
            {"name": "Port_In_2", "cell": (2, 6), "direction": (0, 1), "height": 0.72, "mouth": True, "simple_mouth": True, "width": 0.82},
            {"name": "Port_In_3", "cell": (3, 6), "direction": (0, 1), "height": 0.72, "mouth": True, "simple_mouth": True, "width": 0.82},
        ]
    if size is None:
        return []

    front = ((size[0] - 1) // 2, size[1])
    back = (front[0], -1)
    left = (-1, 0)
    right = (1, 0)
    cell_ports = []
    if kind == "miner_mk1":
        cell_ports = [("Out", 0, front, (0, 1))]
    elif kind in ("smelter", "constructor", "storage"):
        cell_ports = [("In", 0, back, (0, -1)), ("Out", 0, front, (0, 1))]
    elif kind == "geo_tap":
        cell_ports = [("Out", 0, front, (0, 1))]
    elif kind == "assembler":
        cell_ports = [
            ("In", 0, (back[0] - 1, back[1]), (0, -1)),
            ("In", 1, (back[0] + 1, back[1]), (0, -1)),
            ("Out", 0, front, (0, 1)),
        ]
    elif kind == "splitter":
        cell_ports = [
            ("In", 0, back, (0, -1)),
            ("Out", 0, left, (-1, 0)),
            ("Out", 1, front, (0, 1)),
            ("Out", 2, right, (1, 0)),
        ]
    elif kind == "merger":
        cell_ports = [
            ("In", 0, left, (-1, 0)),
            ("In", 1, back, (0, -1)),
            ("In", 2, right, (1, 0)),
            ("Out", 0, front, (0, 1)),
        ]
    elif kind == "belt":
        cell_ports = [
            ("In", 0, back, (0, -1)),
            ("In", 1, left, (-1, 0)),
            ("In", 2, right, (1, 0)),
            ("Out", 0, front, (0, 1)),
        ]

    specs = []
    for label, index, cell, direction in cell_ports:
        missing_junction_mouth = (
            kind == "splitter" and cell == back
        ) or (
            kind == "merger" and cell == front
        )
        specs.append({
            "name": "Port_%s_%d" % (label, index),
            "cell": cell,
            "direction": direction,
            "height": 0.55 if kind in ("splitter", "merger", "belt") else 0.62,
            "mouth": kind in ("miner_mk1", "smelter", "geo_tap", "storage") or missing_junction_mouth,
        })
    return specs


def add_machine_ports(kind, root, static):
    for spec in _port_specs(kind):
        if "position" in spec:
            x, y = spec["position"]
        else:
            size = PORT_FOOTPRINTS[kind]
            cell_x, cell_y = spec["cell"]
            x = cell_x * 2.0 - (size[0] - 1)
            z = cell_y * 2.0 - (size[1] - 1)
            direction_x, direction_z = spec["direction"]
            x -= direction_x
            z -= direction_z
            y = -z

        height = spec["height"]
        direction_x, direction_z = spec["direction"]
        port = empty(spec["name"], root, (x, y, height))
        port.rotation_euler = (0.0, 0.0, math.atan2(-direction_x, -direction_z))
        if not spec.get("mouth", False):
            continue

        width = spec.get("width", 0.9)
        depth = 0.16
        bar = 0.12
        center_x = x + direction_x * 0.06
        center_y = y - direction_z * 0.06
        if spec.get("simple_mouth", False):
            cube(static, spec["name"] + "_Socket", (center_x, center_y, height),
                 (width - bar * 2.0, depth * 0.6, 0.56), "Rubber", 0.0)
            cube(static, spec["name"] + "_Top_Rail",
                 (center_x, center_y, height + 0.32), (width, depth, bar), "Hazard", 0.0)
            cube(static, spec["name"] + "_Bottom_Rail",
                 (center_x, center_y, height - 0.32), (width, depth, bar), "Steel", 0.0)
            continue
        if direction_x:
            cube(static, spec["name"] + "_Socket", (center_x, center_y, height),
                 (depth * 0.6, width - bar * 2.0, 0.56), "Rubber", 0.025)
            for side in (-1.0, 1.0):
                cube(static, spec["name"] + "_Jamb",
                     (center_x, center_y + side * (width * 0.5 - bar * 0.5), height),
                     (depth, bar, 0.76), "Steel", 0.025)
            for side in (-1.0, 1.0):
                cube(static, spec["name"] + "_Rail",
                     (center_x, center_y, height + side * (0.38 - bar * 0.5)),
                     (depth, width, bar), "Hazard" if side > 0 else "Steel", 0.025)
        else:
            cube(static, spec["name"] + "_Socket", (center_x, center_y, height),
                 (width - bar * 2.0, depth * 0.6, 0.56), "Rubber", 0.025)
            for side in (-1.0, 1.0):
                cube(static, spec["name"] + "_Jamb",
                     (center_x + side * (width * 0.5 - bar * 0.5), center_y, height),
                     (bar, depth, 0.76), "Steel", 0.025)
            for side in (-1.0, 1.0):
                cube(static, spec["name"] + "_Rail",
                     (center_x, center_y, height + side * (0.38 - bar * 0.5)),
                     (width, depth, bar), "Hazard" if side > 0 else "Steel", 0.025)


def build_asset(kind, builder):
    clear_scene()
    root, dimensions = builder()
    static = next((child for child in root.children if child.name == "Static_Geometry"), None)
    if static:
        add_machine_ports(kind, root, static)
    if static:
        join_group(static, "Main_Body")
    for group in list(root.children):
        if group.type == "EMPTY" and group.name not in ("Static_Geometry",):
            join_group(group, group.name + "_Mesh")
    objects = list(bpy.context.scene.objects)
    triangles = model_triangles(objects)
    if not (kind.startswith("tree_") or kind.startswith("grass_") or kind in ("hands", "build_tool", "hand_pick")) and not 2000 <= triangles <= 15000:
        raise RuntimeError("%s has %d triangles; expected 2,000–15,000" % (kind, triangles))
    TRI_COUNTS[kind] = triangles
    glb_path = MODEL_DIR / (kind + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    prepare_preview((0.0, 0.0, dimensions[2] * 0.43), max(dimensions))
    bpy.context.scene.render.filepath = str(PREVIEW_DIR / (kind + ".png"))
    bpy.ops.render.render(write_still=True)
    print("MODEL %s: %d triangles, %.1f x %.1f x %.1f m" % (
        kind, triangles, dimensions[0], dimensions[1], dimensions[2]
    ))


def build_requested_assets():
    global PREVIEW_DIR
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    requested = None
    for index, argument in enumerate(arguments):
        if argument == "--only" and index + 1 < len(arguments):
            requested = set(arguments[index + 1].split(","))
        elif argument.startswith("--only="):
            requested = set(argument.split("=", 1)[1].split(","))
        if argument == "--preview-dir" and index + 1 < len(arguments):
            PREVIEW_DIR = Path(arguments[index + 1])
        elif argument.startswith("--preview-dir="):
            PREVIEW_DIR = Path(argument.split("=", 1)[1])
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for name, build in BUILDERS.items():
        if requested is not None and name not in requested:
            continue
        print("Building", name, flush=True)
        build_asset(name, build)

    tri_path = MODEL_DIR / "tri_counts.json"
    counts = json.loads(tri_path.read_text()) if tri_path.exists() else {}
    counts.update(TRI_COUNTS)
    tri_path.write_text(json.dumps(counts, indent=2, sort_keys=True) + "\n")
    print("Wrote", tri_path)


if __name__ == "__main__":
    build_requested_assets()
