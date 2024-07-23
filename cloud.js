import * as THREE from 'three';

import Stats from 'three/addons/libs/stats.module.js';
import {OrbitControls} from "three/addons/controls/OrbitControls.js";
import {Sky} from "three/addons";
import {GUI} from "three/addons/libs/lil-gui.module.min.js";

import fragment from './glsl/fragment.glsl'
import vertex from './glsl/vertex.glsl'

let renderer, scene, camera, stats;

let cube, uniforms;

let sky, sun;

let gui = new GUI();

const clock = new THREE.Clock();

const cloudUniforms = {
    sunTheta: 0.74,
    sunPhi: 1.5,

    sunColor: { r: 204, g: 170, b: 122 },
    sunStrength: 50,

    ambientStrength: 0.1,
    shapeSize: 0.03,
    densityThreshold: 0.02,
    transmittanceThreshold: 0.05,

    cloudSteps: 128,
    cloudStepDelta: 2.,

    lightSteps: 10,
    lightStepDelta: 4,


    updateCloud: function() {
        let uniforms = cube.material.uniforms;

        const sun = new THREE.Vector3();
        uniforms.u_sunDirection.value = sun.setFromSphericalCoords(1, this.sunPhi, this.sunTheta);
        sky.material.uniforms.sunPosition.value.copy(sun);
        uniforms.u_sunColor.value = new THREE.Vector3(this.sunColor.r / 255, this.sunColor.g / 255, this.sunColor.b / 255);
        uniforms.u_sunStrength.value = this.sunStrength;

        uniforms.u_ambientStrength.value = this.ambientStrength;
        uniforms.u_shapeSize.value = this.shapeSize;
        uniforms.u_densityThreshold.value = this.densityThreshold;
        uniforms.u_transmittanceThreshold.value = this.transmittanceThreshold;

        uniforms.u_cloudSteps.value = this.cloudSteps;
        uniforms.u_cloudStepDelta.value = this.cloudStepDelta;

        uniforms.u_lightSteps.value = this.lightSteps;
        uniforms.u_lightStepDelta.value = this.lightStepDelta;
    }
};

clock.start()

init().then(() => animate());

async function init() {

    camera = new THREE.PerspectiveCamera(30, window.innerWidth / window.innerHeight, 1, 10000);
    camera.position.z = 200;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(0xbfd1e5);

    uniforms = {
        u_eps: { value: 0.001 },
        u_maxDis: { value: 1e10 },
        u_maxSteps: { value: 600 },

        u_camPos: { value: camera.position },
        u_camToWorldMat: { value: camera.matrixWorld },
        u_camInvProjMat: { value: camera.projectionMatrixInverse },

        u_time: { value: 0 },

        u_resolution: {value: new THREE.Vector2(window.innerWidth, window.innerHeight)},

        u_sunDirection: { value: new THREE.Vector3().setFromSphericalCoords(1, cloudUniforms.sunPhi, cloudUniforms.sunTheta) },
        u_sunColor: { value: new THREE.Vector3(cloudUniforms.sunColor.r / 255, cloudUniforms.sunColor.g / 255, cloudUniforms.sunColor.b / 255) },
        u_sunStrength: { value: cloudUniforms.sunStrength },

        u_ambientStrength: { value: cloudUniforms.ambientStrength },
        u_shapeSize: { value: cloudUniforms.shapeSize },
        u_densityThreshold: { value: cloudUniforms.densityThreshold },
        u_transmittanceThreshold: { value: cloudUniforms.densityThreshold },

        u_cloudSteps: { value: cloudUniforms.cloudSteps },
        u_cloudStepDelta: { value: cloudUniforms.cloudStepDelta },

        u_lightSteps: { value: cloudUniforms.lightSteps },
        u_lightStepDelta: { value: cloudUniforms.lightStepDelta },
    };

    let fShader = fragment;
    let vShader = vertex;

    console.log(fShader, vShader)

    const shaderMaterial = new THREE.ShaderMaterial({
        uniforms: uniforms,
        vertexShader: vShader,
        fragmentShader: fShader,
        side: THREE.BackSide,
        transparent: true
    });

    const geometry = new THREE.BoxGeometry(100, 100, 100, 1, 1, 1);

    cube = new THREE.Mesh(geometry, shaderMaterial);
    scene.add(cube);
    //scene.add(new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({color: 'green', wireframe: true})));

    renderer = new THREE.WebGLRenderer();
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 0.15;

    const container = document.getElementById('container');
    container.appendChild(renderer.domElement);

    stats = new Stats();
    container.appendChild(stats.dom);

    const controls = new OrbitControls( camera, renderer.domElement );
    controls.target.set( 0, 0, 0 );
    controls.update();

    initSky();

    initCloudGui();

    window.addEventListener('resize', () => {
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();

        if (renderer) renderer.setSize(window.innerWidth, window.innerHeight);
    });

}

function initCloudGui() {
    const folder = gui.addFolder('Cloud');

    folder.add(cloudUniforms, 'sunTheta', 0, 2 * Math.PI );
    folder.add(cloudUniforms, 'sunPhi', -Math.PI / 2, Math.PI / 2);

    folder.addColor(cloudUniforms, 'sunColor', 255);
    folder.add(cloudUniforms, 'sunStrength', 0, 100);
    folder.add(cloudUniforms, 'ambientStrength', 0, 1);
    folder.add(cloudUniforms, 'shapeSize', 0, 0.1);
    folder.add(cloudUniforms, 'densityThreshold', 0, 0.3);
    folder.add(cloudUniforms, 'transmittanceThreshold', 0, 0.5);

    folder.add(cloudUniforms, 'cloudSteps', 0, 256);
    folder.add(cloudUniforms, 'cloudStepDelta', 0, 10);

    folder.add(cloudUniforms, 'lightSteps', 0, 256);
    folder.add(cloudUniforms, 'lightStepDelta', 0, 10);

    folder.add(cloudUniforms, 'updateCloud');

}

function initSky() {

    // Add Sky
    sky = new Sky();
    sky.scale.setScalar( 450000 );
    scene.add( sky );

    sun = new THREE.Vector3();

    /// GUI

    const effectController = {
        turbidity: 10,
        rayleigh: 3,
        mieCoefficient: 0.005,
        mieDirectionalG: 0.7,
        elevation: 10,
        azimuth: -140,
        exposure: renderer.toneMappingExposure
    };

    function guiChanged() {

        const uniforms = sky.material.uniforms;
        uniforms[ 'turbidity' ].value = effectController.turbidity;
        uniforms[ 'rayleigh' ].value = effectController.rayleigh;
        uniforms[ 'mieCoefficient' ].value = effectController.mieCoefficient;
        uniforms[ 'mieDirectionalG' ].value = effectController.mieDirectionalG;

        sun.setFromSphericalCoords( 1, cloudUniforms.sunPhi, cloudUniforms.sunTheta );

        uniforms[ 'sunPosition' ].value.copy( sun );

        renderer.toneMappingExposure = effectController.exposure;

    }

    const folder = gui.addFolder('Sky');

    folder.add( effectController, 'turbidity', 0.0, 20.0, 0.1 ).onChange( guiChanged );
    folder.add( effectController, 'rayleigh', 0.0, 4, 0.001 ).onChange( guiChanged );
    folder.add( effectController, 'mieCoefficient', 0.0, 0.1, 0.001 ).onChange( guiChanged );
    folder.add( effectController, 'mieDirectionalG', 0.0, 1, 0.001 ).onChange( guiChanged );
    folder.add( effectController, 'exposure', 0, 1, 0.0001 ).onChange( guiChanged );

    guiChanged();

}


function animate() {
    cube.material.uniforms.u_time.value = clock.getElapsedTime();

    requestAnimationFrame( animate );

    render();
    stats.update();

}

function render() {

    renderer.render( scene, camera );

}